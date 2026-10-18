#!/usr/bin/env bash
# GitLab-API (wordt gesourced door run.sh). Nodig: GITLAB_TOKEN, GITLAB_GROUP,
# optioneel GITLAB_BASE_URL.

gitlab_api() {  # <pad-met-query>; schrijft de JSON naar stdout
  curl -fsS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
    "${GITLAB_BASE_URL:-https://gitlab.com}/api/v4/$1"
}

# Open MR's van migraties in de groep (label "migratie" plus het label met de naam van
# de migratie), als regels "<project-pad><TAB><overige labels, komma-gescheiden>".
open_migratie_mrs() {
  local groep page=1 resp n
  groep="$(jq -rn --arg g "$GITLAB_GROUP" '$g | @uri')"
  while :; do
    resp="$(gitlab_api "groups/$groep/merge_requests?state=opened&labels=migratie&per_page=100&page=$page")" || return 1
    n="$(jq length <<< "$resp")"
    jq -r '.[] | [(.references.full | sub("!.*$"; "")), ((.labels - ["migratie"]) | join(","))] | @tsv' <<< "$resp"
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
  done
}

# Projecten in de groep (inclusief subgroepen, zonder gearchiveerde), als regels
# "<id><TAB><pad><TAB><default-branch>".
groep_projecten() {
  local groep page=1 resp n
  groep="$(jq -rn --arg g "$GITLAB_GROUP" '$g | @uri')"
  while :; do
    resp="$(gitlab_api "groups/$groep/projects?include_subgroups=true&archived=false&per_page=100&page=$page")" || return 1
    n="$(jq length <<< "$resp")"
    jq -r '.[] | [.id, .path_with_namespace, (.default_branch // "main")] | @tsv' <<< "$resp"
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
  done
}
