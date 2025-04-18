module.exports = {
  "username": "trap-renovate[bot]",
  "gitAuthor": "trap-renovate <138502363+trap-renovate[bot]@users.noreply.github.com>",
  "repositories": ["traPtitech/manifest"],
  "hostRules": [
    {
      "hostType": "docker",
      "matchHost": "ghcr.io",
      "username": "trapyojo",
      "password": process.env.RENOVATE_GITHUB_PAT
    }
  ]
}
