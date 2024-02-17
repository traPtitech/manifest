package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/samber/lo"
	"github.com/schollz/progressbar/v3"
	log "github.com/sirupsen/logrus"
	"github.com/sourcegraph/conc"
	"github.com/sourcegraph/conc/pool"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	readObjectPrefix = flag.String("read-object-prefix", "trap-wasabi-registry:/trap-ns-registry/", "rclone object prefix")
	doit             = flag.Bool("doit", false, "Disable dryrun and actually delete files")
	deleteRepoPrefix = "ns-apps-tmp/"
	gcRepoPrefix     = "ns-apps/"
)

func init() {
	flag.Parse()
}

var (
	digestPattern     = regexp.MustCompile("^[0-9a-f]{64}$")
	uploadsPattern    = regexp.MustCompile("^(docker/registry/v2/repositories/[^/]+/[^/]+/_uploads/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/).+$")
	blobPattern       = regexp.MustCompile("^docker/registry/v2/blobs/sha256/[0-9a-f]{2}/([0-9a-f]{64})/data$")
	layersPattern     = regexp.MustCompile("^docker/registry/v2/repositories/([^/]+/[^/]+)/_layers/sha256/([0-9a-f]{64})/link$")
	revisionsPattern  = regexp.MustCompile("^docker/registry/v2/repositories/([^/]+/[^/]+)/_manifests/revisions/sha256/([0-9a-f]{64})/link$")
	currentTagPattern = regexp.MustCompile("^docker/registry/v2/repositories/([^/]+/[^/]+)/_manifests/tags/([^/]+)/current/link$")
	tagPattern        = regexp.MustCompile("^docker/registry/v2/repositories/([^/]+/[^/]+)/_manifests/tags/([^/]+)/index/sha256/([0-9a-f]{64})/link$")
)

func constructBlobPath(digest string) string {
	return fmt.Sprintf("docker/registry/v2/blobs/sha256/%s/%s/data", digest[:2], digest)
}

var objects map[string]*Object

type Object struct {
	Size     int
	Modified time.Time
	Path     string
}

type Uploads struct {
	StartedAt time.Time
	Objects   []*Object
}

type Repository struct {
	Layers            map[string]*Object        // SHA256 digest to object
	ManifestRevisions map[string]*Object        // SHA256 digest to object
	Tags              map[string]*RepositoryTag // Tag name to tag data
}

type RepositoryTag struct {
	CurrentBlob   string // SHA256 digest pointed by CurrentObject
	CurrentObject *Object
	Objects       map[string]*Object // SHA256 digest to object
}

func cmdExec(name string, args ...string) ([]byte, error) {
	var buf bytes.Buffer
	cmd := exec.Command(name, args...)
	cmd.Stdout = &buf
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}

var remoteReqSem = make(chan struct{}, 30)

func readObject(path string) ([]byte, error) {
	remoteReqSem <- struct{}{}
	defer func() {
		<-remoteReqSem
	}()
	log.Debugf("Reading object %v", path)
	return cmdExec("rclone", "cat", *readObjectPrefix+path)
}

func deleteObject(path string) error {
	remoteReqSem <- struct{}{}
	defer func() {
		<-remoteReqSem
	}()
	log.Debugf("Deleting object %v", path)
	_, err := cmdExec("rclone", "deletefile", *readObjectPrefix+path)
	return err
}

func getReachableBlobs(digest string) []string {
	objectPath := constructBlobPath(digest)
	digests := []string{digest}

	if _, ok := objects[objectPath]; !ok {
		log.Warnf("Object %v does not exist, skipping", objectPath)
		return nil
	}

	b := lo.Must(readObject(objectPath))

	var m map[string]any
	lo.Must0(json.Unmarshal(b, &m))

	// https://github.com/openshift/docker-distribution/blob/master/docs/spec/manifest-v2-2.md
	// https://github.com/opencontainers/image-spec/blob/main/image-index.md
	switch mediaType := m["mediaType"]; mediaType {
	case "application/vnd.oci.image.index.v1+json":
		manifests := m["manifests"].([]any)
		manifestDigests := lo.Map(manifests, func(manifest any, _ int) string {
			manifestObj := manifest.(map[string]any)
			manifestDigest := manifestObj["digest"].(string)
			return strings.TrimPrefix(manifestDigest, "sha256:")
		})
		p := pool.NewWithResults[[]string]()
		for _, manifestDigest := range manifestDigests {
			p.Go(func() []string {
				return getReachableBlobs(manifestDigest)
			})
		}
		for _, childDigests := range p.Wait() {
			digests = append(digests, childDigests...)
		}
		return digests
	case "application/vnd.docker.distribution.manifest.v2+json", "application/vnd.oci.image.manifest.v1+json":
		configDigest := m["config"].(map[string]any)["digest"].(string)
		configDigest = strings.TrimPrefix(configDigest, "sha256:")
		digests = append(digests, configDigest)

		layers := m["layers"].([]any)
		layerDigests := lo.Map(layers, func(manifest any, _ int) string {
			manifestObj := manifest.(map[string]any)
			manifestDigest := manifestObj["digest"].(string)
			return strings.TrimPrefix(manifestDigest, "sha256:")
		})
		digests = append(digests, layerDigests...)
		return digests
	default:
		panic(fmt.Sprintf("unknown mediaType: %v", mediaType))
	}
}

func main() {
	//log.SetLevel(log.DebugLevel)
	if *doit {
		log.Warnf("Dryrun disabled! This run WILL DELETE files.")
	}

	// Read the output of "rclone lsl"
	log.Infof("Listing objects ...")
	b := lo.Must(cmdExec("rclone", "lsl", *readObjectPrefix))
	//b := lo.Must(io.ReadAll(os.Stdin)) // or from stdin
	s := strings.Trim(string(b), "\n")
	lines := strings.Split(s, "\n")

	log.Infof("Reading objects ...")
	objects = lo.SliceToMap(lines, func(line string) (string, *Object) {
		fields := strings.Fields(line)
		if len(fields) != 4 {
			panic(fmt.Sprintf("expected line to have 4 fields, but has %v fields: %v", len(fields), line))
		}

		size, modified, path := fields[0], fields[1]+" "+fields[2], fields[3]
		return path, &Object{
			Size:     lo.Must(strconv.Atoi(size)),
			Modified: lo.Must(time.ParseInLocation("2006-01-02 15:04:05.999999999", modified, time.Local)),
			Path:     path,
		}
	})
	blobs := make(map[string]*Object)
	uploads := make(map[string]*Uploads) // uploads prefix to uploads metadata
	repos := make(map[string]*Repository)
	ensureRepoMap := func(repoName string) {
		if _, ok := repos[repoName]; !ok {
			repos[repoName] = &Repository{
				Layers:            make(map[string]*Object),
				ManifestRevisions: make(map[string]*Object),
				Tags:              make(map[string]*RepositoryTag),
			}
		}
	}
	ensureTagMap := func(repoName, tagName string) {
		if _, ok := repos[repoName].Tags[tagName]; !ok {
			repos[repoName].Tags[tagName] = &RepositoryTag{
				CurrentBlob:   "",
				CurrentObject: nil,
				Objects:       make(map[string]*Object),
			}
		}
	}
	for _, object := range lo.Values(objects) {
		switch {
		case uploadsPattern.MatchString(object.Path):
			m := uploadsPattern.FindStringSubmatch(object.Path)
			prefix := m[1]
			if _, ok := uploads[prefix]; !ok {
				uploads[prefix] = &Uploads{}
			}
			uploads[prefix].Objects = append(uploads[prefix].Objects, object)
		case blobPattern.MatchString(object.Path):
			m := blobPattern.FindStringSubmatch(object.Path)
			blobs[m[1]] = object
		case layersPattern.MatchString(object.Path):
			m := layersPattern.FindStringSubmatch(object.Path)
			ensureRepoMap(m[1])
			repos[m[1]].Layers[m[2]] = object
		case revisionsPattern.MatchString(object.Path):
			m := revisionsPattern.FindStringSubmatch(object.Path)
			ensureRepoMap(m[1])
			repos[m[1]].ManifestRevisions[m[2]] = object
		case currentTagPattern.MatchString(object.Path):
			m := currentTagPattern.FindStringSubmatch(object.Path)
			ensureRepoMap(m[1])
			ensureTagMap(m[1], m[2])
			if repos[m[1]].Tags[m[2]].CurrentObject != nil {
				panic(fmt.Sprintf("multiple current object read: %v", object.Path))
			}
			repos[m[1]].Tags[m[2]].CurrentObject = object
		case tagPattern.MatchString(object.Path):
			m := tagPattern.FindStringSubmatch(object.Path)
			ensureRepoMap(m[1])
			ensureTagMap(m[1], m[2])
			repos[m[1]].Tags[m[2]].Objects[m[3]] = object
		default:
			panic(fmt.Sprintf("unknown object path pattern: %v", object.Path))
		}
	}

	// Read uploads "startedat"
	log.Infof("Reading _uploads date ...")
	wg := conc.NewWaitGroup()
	for prefix, upload := range uploads {
		wg.Go(func() {
			str := string(lo.Must(readObject(prefix + "startedat")))
			t, err := time.Parse(time.RFC3339, str)
			upload.StartedAt = lo.Must(t, err, fmt.Sprintf("%vstartedat has invalid format: %v", prefix, str))
		})
	}
	wg.Wait()

	// Read current tag links
	log.Infof("Reading current tag links ...")
	for repoName, repo := range repos {
		for tagName, tag := range repo.Tags {
			if tag.CurrentObject == nil {
				panic(fmt.Sprintf("%v:%v current tag link is nil", repoName, tagName))
			}
			wg.Go(func() {
				digest := strings.TrimPrefix(string(lo.Must(readObject(tag.CurrentObject.Path))), "sha256:")
				if !digestPattern.MatchString(digest) {
					panic(fmt.Sprintf("expected to match digest pattern: %v", digest))
				}
				tag.CurrentBlob = digest
			})
		}
	}
	wg.Wait()

	log.Infof("Objects %d", len(objects))
	log.Infof(" -> Blobs %d", len(blobs))
	log.Infof(" -> Repositories %d", len(repos))

	// Calculate reachable blobs
	log.Infof("Calculating reachable blobs ...")

	reachableDigests := make(map[string]struct{})
	p := pool.NewWithResults[[]string]()
	for repoName, repo := range repos {
		if strings.HasPrefix(repoName, deleteRepoPrefix) {
			log.Infof("Not counting repo %v ...", repoName)
			continue
		}
		for tagName, tag := range repo.Tags {
			if strings.HasPrefix(repoName, gcRepoPrefix) && len(tag.Objects) >= 2 {
				log.Infof("Not counting tag %v:%v as it has 2 or more tag objects ...", repoName, tagName)
				continue
			}
			for digest := range tag.Objects {
				p.Go(func() []string {
					return getReachableBlobs(digest)
				})
			}
		}
	}
	for _, digests := range p.Wait() {
		for _, digest := range digests {
			reachableDigests[digest] = struct{}{}
		}
	}
	log.Infof("%d reachable blobs found", len(reachableDigests))

	// Check unreachable objects
	{
		// Check old _uploads directory
		var deletableUploads []*Object
		deleteUploadOlderThan := time.Now().Add(-time.Hour)
		for _, upload := range uploads {
			if upload.StartedAt.Before(deleteUploadOlderThan) {
				deletableUploads = append(deletableUploads, upload.Objects...)
			}
		}

		// Check unreachable blobs
		var unreachableBlobs []*Object
		for digest, blob := range blobs {
			if _, ok := reachableDigests[digest]; !ok {
				unreachableBlobs = append(unreachableBlobs, blob)
			}
		}

		// Check unreachable repository objects
		var (
			unreachableLayers     []*Object
			unreachableRevisions  []*Object
			unreachableTags       []*Object
			unreachableTagObjects []*Object
		)
		for _, repo := range repos {
			for digest, object := range repo.Layers {
				if _, ok := reachableDigests[digest]; !ok {
					unreachableLayers = append(unreachableLayers, object)
				}
			}
			for digest, object := range repo.ManifestRevisions {
				if _, ok := reachableDigests[digest]; !ok {
					unreachableRevisions = append(unreachableRevisions, object)
				}
			}
			for _, tag := range repo.Tags {
				_, tagCurrentReachable := reachableDigests[tag.CurrentBlob]
				if !tagCurrentReachable {
					unreachableTags = append(unreachableTags, tag.CurrentObject)
				}
				for digest, object := range tag.Objects {
					if _, ok := reachableDigests[digest]; !ok || !tagCurrentReachable { // delete all tag objects if current link is not reachable
						unreachableTagObjects = append(unreachableTagObjects, object)
					}
				}
			}
		}

		log.Infof("%d old _uploads objects found eligible for deletion", len(deletableUploads))
		log.Infof("%d unreachable blobs found", len(unreachableBlobs))
		log.Infof("%d unreachable layers found", len(unreachableLayers))
		log.Infof("%d unreachable revisions found", len(unreachableRevisions))
		log.Infof("%d unreachable tags found", len(unreachableTags))
		log.Infof("%d unreachable tag objects found", len(unreachableTagObjects))

		deletionCandidates := concat(deletableUploads, unreachableBlobs, unreachableLayers, unreachableRevisions, unreachableTags, unreachableTagObjects)
		deleteObjectOlderThan := time.Now().Add(-time.Hour) // Do not delete objects that have uploads in progress
		objectsToDelete := lo.Filter(deletionCandidates, func(object *Object, _ int) bool { return object.Modified.Before(deleteObjectOlderThan) })
		log.Infof("%d objects are candidates for deletion; of which, %d objects are old enough and safe to delete", len(deletionCandidates), len(objectsToDelete))
		estimatedFreedBytes := lo.SumBy(objectsToDelete, func(upload *Object) int { return upload.Size })
		prettyFreedBytes := message.NewPrinter(language.English).Sprintf("%d", estimatedFreedBytes)
		log.Infof("Estimated freed bytes %v bytes", prettyFreedBytes)

		// Execute deletion
		if *doit {
			log.Infof("Deleting files ...")
			bar := progressbar.Default(int64(len(objectsToDelete)))
			for _, object := range objectsToDelete {
				wg.Go(func() {
					lo.Must0(deleteObject(object.Path))
					lo.Must0(bar.Add(1))
				})
			}
			wg.Wait()
			log.Infof("Deletion complete.")
		} else {
			log.Infof("Dryrun enabled, not actually deleting files. Instead, here is the list of files planned to be deleted:")
			now := time.Now()
			for _, object := range objectsToDelete {
				fmt.Printf("%v B, %v (%v ago): %v\n", object.Size, object.Modified, now.Sub(object.Modified), object.Path)
			}
		}
	}
}

func concat[T any](s ...[]T) []T {
	var res []T
	for _, ss := range s {
		res = append(res, ss...)
	}
	return res
}
