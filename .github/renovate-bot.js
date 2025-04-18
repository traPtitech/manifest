module.exports = {
  "username": "trap-renovate[bot]",
  "gitAuthor": "trap-renovate <138502363+trap-renovate[bot]@users.noreply.github.com>",
  "repositories": ["traPtitech/manifest"],
  "hostRules": [
    {
      "matchHost": "https://api.github.com/repos/traPtitech/portal",
      "username": "trapyojo",
      "token": process.env.RENOVATE_GITHUB_PAT
    },
    {
      "matchHost": "https://github.domain.com/api/v3/repos/traPtitech/portal",
      "username": "trapyojo",
      "token": process.env.RENOVATE_GITHUB_PAT
    },
    {
      "matchHost": "https://api.github.com/repos/traPtitech/portal-UI",
      "username": "trapyojo",
      "token": process.env.RENOVATE_GITHUB_PAT
    },
    {
      "matchHost": "https://github.domain.com/api/v3/repos/traPtitech/portal-UI",
      "username": "trapyojo",
      "token": process.env.RENOVATE_GITHUB_PAT
    }
  ]
}
