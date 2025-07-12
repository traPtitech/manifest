module.exports = {
  hostRules: [
    {
      hostType: "docker",
      matchHost: "ghcr.io",
      username: "trapyojo",
      password: process.env.RENOVATE_GITHUB_PAT
    }
  ]
}