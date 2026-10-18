// Jenkins-pipeline voor migratie-tools: één migratie over de GitLab-groep via run.sh.
// Draait zonder Docker op een Linux-agent; de tools komen uit jenkins/gereedschap.sh.
//
// Nodig in Jenkins (namen hieronder aanpassen aan jullie installatie):
//   - een agent met label 'linux' met bash, git, curl, tar, python3 (+ venv), Java en Maven
//   - credential 'gitlab-migratie-token' (Secret text): GitLab-token met api-rechten op de groep
//   - credential 'template-repo-lezen' (Username with password): leesrechten op de
//     template-repo, voor git via HTTPS (Git-plugin, binding gitUsernamePassword).
//     Gebruikt de template-repo SSH, vervang die binding dan door sshagent(['…']).
//   - Maven-instellingen (Nexus-mirror) zoals jullie andere Maven-builds die krijgen; de
//     builds van de services gebruiken de settings.xml en ~/.m2 van de agent.
//
// Handmatig starten: vul MIGRATIE in (naam uit migraties/ of pad), standaard een dry-run.
// Wekelijkse opschoning: zet de cron-trigger aan; een geplande build maakt dan zelf
// migraties/opschoning-<jaar>-w<week>.env aan en draait die met --go.

pipeline {
    agent { label 'linux' }

    options {
        disableConcurrentBuilds()      // twee runs tegelijk zien elkaars open MR's niet goed
        timestamps()
        timeout(time: 4, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        string(name: 'MIGRATIE', defaultValue: '',
               description: 'Naam uit migraties/ (zonder .env) of pad naar een migratiebestand')
        booleanParam(name: 'GO', defaultValue: false,
                     description: "Echt uitvoeren en MR's aanmaken. Uit: dry-run, er wordt niets gepusht")
        string(name: 'REPO_INCLUDE', defaultValue: '',
               description: 'Alleen services waarvan de naam matcht (regex). Leeg: de hele groep')
        booleanParam(name: 'ZONDER_VERIFY', defaultValue: false,
                     description: 'Build en tests van de services overslaan (alleen bij een dry-run)')
    }

    // triggers { cron('H 6 * * 1') }   // wekelijkse opschoning op maandagochtend

    // Gebruiken jullie Jenkins' eigen JDK- en Maven-installaties, zet dan de namen uit
    // Global Tool Configuration hier neer; anders komen java en mvn uit het PATH van de agent.
    // tools { jdk 'jdk-21'; maven 'maven-3.9' }

    environment {
        GITLAB_GROUP    = 'mijn-groep'
        GITLAB_BASE_URL = 'https://gitlab.example.com'
        CONCURRENT      = '4'
        // UITSLUITLIJST = 'gedeelde-lib infra-config'

        // Achter een afgeschermd netwerk: de downloads van gereedschap.sh via Nexus.
        // PIP_INDEX_URL      = 'https://nexus.example.com/repository/pypi-proxy/simple'
        // MULTI_GITTER_BASIS = 'https://nexus.example.com/repository/github/lindell/multi-gitter/releases/download'
        // JQ_BASIS           = 'https://nexus.example.com/repository/github/jqlang/jq/releases/download'

        // Auteur van de commits in de services.
        GIT_AUTHOR_NAME     = 'migratie-tools'
        GIT_AUTHOR_EMAIL    = 'migratie-tools@example.com'
        GIT_COMMITTER_NAME  = 'migratie-tools'
        GIT_COMMITTER_EMAIL = 'migratie-tools@example.com'
    }

    stages {
        stage('Gereedschap') {
            steps {
                sh 'jenkins/gereedschap.sh .tools'
            }
        }

        stage('Migratie kiezen') {
            steps {
                script {
                    def gepland = !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause').isEmpty()
                    if (gepland) {
                        env.MIGRATIE_NAAM = sh(script: 'echo "opschoning-$(date +%G-w%V)"', returnStdout: true).trim()
                        writeFile file: "migraties/${env.MIGRATIE_NAAM}.env",
                                  text: "# Wekelijkse opschoning, aangemaakt door Jenkins.\nRECEPT=local.migratietools.WekelijkseOpschoning\n"
                        env.GO_VLAG = '--go'
                    } else {
                        if (!params.MIGRATIE?.trim()) {
                            error('Vul MIGRATIE in: een naam uit migraties/ of een pad')
                        }
                        if (params.GO && params.ZONDER_VERIFY) {
                            error('ZONDER_VERIFY mag alleen bij een dry-run')
                        }
                        env.MIGRATIE_NAAM = params.MIGRATIE.trim()
                        env.GO_VLAG = params.GO ? '--go' : ''
                    }
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.MIGRATIE_NAAM}" + (env.GO_VLAG ? '' : ' (dry-run)')
                }
            }
        }

        stage('Migratie') {
            steps {
                withCredentials([
                    string(credentialsId: 'gitlab-migratie-token', variable: 'GITLAB_TOKEN'),
                    gitUsernamePassword(credentialsId: 'template-repo-lezen', gitToolName: 'Default')
                ]) {
                    sh '''
                        export PATH="$PWD/.tools/bin:$PWD/.tools/venv/bin:$PATH"
                        export CRUFT_PYTHON="$PWD/.tools/venv/bin/python"
                        rm -rf runs
                        set -- "$MIGRATIE_NAAM" $GO_VLAG
                        [ -z "$REPO_INCLUDE" ] || set -- "$@" --repo-include "$REPO_INCLUDE"
                        [ "$ZONDER_VERIFY" != true ] || set -- "$@" --zonder-verify
                        ./run.sh "$@"
                    '''
                }
            }
        }
    }

    post {
        always {
            // resultaten.tsv en per service de patches, uitvoer en stand bij handwerk
            archiveArtifacts artifacts: 'runs/**', allowEmptyArchive: true
            script {
                def overzicht = sh(returnStdout: true, script: '''
                    f="$(ls runs/*/resultaten.tsv 2>/dev/null | head -1)"
                    [ -n "$f" ] || exit 0
                    awk -F'\t' '{ n[$2]++ } END { for (u in n) printf "%s: %d   ", u, n[u] }' "$f"
                ''').trim()
                def handwerk = sh(returnStdout: true, script: '''
                    f="$(ls runs/*/resultaten.tsv 2>/dev/null | head -1)"
                    [ -n "$f" ] && awk -F'\t' '$2 == "Handwerk nodig"' "$f" | wc -l || echo 0
                ''').trim().toInteger()
                if (overzicht) {
                    currentBuild.description = overzicht
                }
                if (handwerk > 0) {
                    unstable("Handwerk nodig bij ${handwerk} service(s); zie runs/*/resultaten.tsv in de artefacten")
                }
            }
        }
    }
}
