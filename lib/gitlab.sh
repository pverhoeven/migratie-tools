#!/usr/bin/env bash
# GitLab-API (wordt gesourced door run.sh). Nodig: GITLAB_TOKEN, GITLAB_GROUP,
# optioneel GITLAB_BASE_URL.

gitlab_api() {  # <pad-met-query>; schrijft de JSON naar stdout
  # De header via stdin, niet als argument (dan staat het token in de proceslijst) en
  # niet via <(...): curl op Windows (Git Bash) kan /dev/fd/... niet lezen.
  # CURL_OPTS (config.env): extra opties voor curl, bv. --ssl-revoke-best-effort.
  # shellcheck disable=SC2086
  printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN" \
    | curl -fsS ${CURL_OPTS:-} -H @- "${GITLAB_BASE_URL:-https://gitlab.com}/api/v4/$1"
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

# Alle MR's van één migratie in de groep (labels "migratie" en de naam), in elke
# toestand, als regels "<project-id><TAB><project-pad><TAB><iid><TAB><state><TAB>
# <aangemaakt><TAB><dagen open><TAB><conflict met de doelbranch: true|false><TAB><url>".
migratie_mrs() {  # <naam van de migratie>
  local groep labels page=1 resp n
  groep="$(jq -rn --arg g "$GITLAB_GROUP" '$g | @uri')"
  labels="$(jq -rn --arg l "migratie,$1" '$l | @uri')"
  while :; do
    resp="$(gitlab_api "groups/$groep/merge_requests?state=all&labels=$labels&per_page=100&page=$page")" || return 1
    n="$(jq length <<< "$resp")"
    jq -r '.[] | [.project_id, (.references.full | sub("!.*$"; "")), .iid, .state, .created_at,
                  ((now - (.created_at | sub("\\.[0-9]+"; "") | fromdateiso8601)) / 86400 | floor),
                  (.has_conflicts // false), .web_url] | @tsv' <<< "$resp"
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
  done
}

# De status van de laatste pipeline van een MR (success, failed, running, ...), of "geen".
mr_pipeline() {  # <project-id> <iid>
  gitlab_api "projects/$1/merge_requests/$2" | jq -r '.head_pipeline.status // "geen"'
}
