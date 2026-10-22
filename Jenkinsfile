// Jenkins-pipeline voor migratie-tools: één migratie over de GitLab-groep via run.sh.
// Draait zonder Docker op een Linux-agent; de tools komen uit jenkins/gereedschap.sh.
//
// Deze Jenkinsfile bevat geen instellingen van een organisatie: alles komt uit
// omgevingsvariabelen die je in Jenkins zelf zet (bv. als folder properties op de map
// van de job, of als globale eigenschappen). Zie "Jenkins" in de README.
//
//   Verplicht
//     GITLAB_GROUP                    GitLab-groep met de services
//     GITLAB_BASE_URL                 URL van GitLab (leeg: gitlab.com)
//     MIGRATIE_GITLAB_CREDENTIALS     id van een Secret text-credential: GitLab-token met api-rechten
//   Optioneel
//     MIGRATIE_TEMPLATE_CREDENTIALS   id van een Username with password-credential met leesrechten
//                                     op de template-repo (git via HTTPS)
//     MIGRATIE_JDK, MIGRATIE_MAVEN    namen van JDK- en Maven-installaties in Jenkins (Tools);
//                                     leeg: java en mvn uit het PATH van de agent. JDK 21 of nieuwer.
//     MIGRATIE_SJABLOON               migratie die deze job steeds opnieuw draait, als ronde
//                                     (bv. opschoning of cruft-update); zie hieronder
//     MIGRATIE_RONDE                  datumformaat van de ronde (standaard '%G-w%V', per week;
//                                     bv. '%Y-%m' voor maandelijks)
//     MIGRATIE_CRON                   cron voor geplande builds, bv. 'H 6 * * 1'; leeg: uit
//     MIGRATIE_GIT_NAAM, MIGRATIE_GIT_EMAIL
//                                     auteur van de commits in de services
//     MIGRATIE_EIGEN_REPO             git-URL van een eigen (interne) repo met migraties/ en/of
//                                     recepten/; die worden naast die van migratie-tools gebruikt
//     MIGRATIE_EIGEN_BRANCH           branch daarvan (standaard main)
//     MIGRATIE_EIGEN_CREDENTIALS      id van een credential om die repo te lezen
//     CONCURRENT, UITSLUITLIJST, BRANCH_PREFIX, WAARSCHUW_OVERGESLAGEN
//                                     zoals in config.env.example
//     PIP_INDEX_URL, MULTI_GITTER_BASIS, JQ_BASIS
//                                     downloads via een mirror (bv. Nexus), zie jenkins/gereedschap.sh
//
// Meerdere jobs, één Jenkinsfile: geef elke job (of map) zijn eigen MIGRATIE_SJABLOON en
// MIGRATIE_CRON. Een build van het sjabloon maakt er een ronde van, bv.
// migraties/opschoning-2026-w43.env, zodat elke ronde een eigen branch krijgt.
//   - geplande build: de ronde van het sjabloon, met --go
//   - handmatige build: MIGRATIE als die is ingevuld, anders de ronde van het sjabloon;
//     standaard een dry-run (GO)

pipeline {
    agent any

    options {
        disableConcurrentBuilds()      // twee runs tegelijk zien elkaars open MR's niet goed
        timestamps()
        timeout(time: 4, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        string(name: 'MIGRATIE', defaultValue: '',
               description: 'Naam (zonder .env) of pad van een migratiebestand. Leeg: de ronde van MIGRATIE_SJABLOON')
        booleanParam(name: 'GO', defaultValue: false,
                     description: "Echt uitvoeren en MR's aanmaken. Uit: dry-run, er wordt niets gepusht")
        string(name: 'REPO_INCLUDE', defaultValue: '',
               description: 'Alleen services waarvan de naam matcht (regex). Leeg: de hele groep')
        booleanParam(name: 'ZONDER_VERIFY', defaultValue: false,
                     description: 'Build en tests van de services overslaan (alleen bij een dry-run)')
    }

    triggers {
        cron(env.MIGRATIE_CRON ?: '')
    }

    environment {
        LANG = 'C.UTF-8'   // de uitvoer bevat ë, → en ─
    }

    stages {
        stage('Instellingen') {
            steps {
                script {
                    def ontbreekt = []
                    if (!env.GITLAB_GROUP) { ontbreekt << 'GITLAB_GROUP' }
                    if (!env.MIGRATIE_GITLAB_CREDENTIALS) { ontbreekt << 'MIGRATIE_GITLAB_CREDENTIALS' }
                    if (ontbreekt) {
                        error("Zet in Jenkins (bv. als folder property): ${ontbreekt.join(', ')}. Zie de Jenkinsfile en de README.")
                    }
                    // De tools staan buiten de workspace (die wordt na afloop opgeruimd), zodat
                    // ze niet bij elke build opnieuw worden gedownload.
                    env.GEREEDSCHAP = sh(returnStdout: true, script: 'echo "$HOME/.cache/migratie-tools"').trim()
                }
            }
        }

        stage('Eigen migraties en recepten') {
            when {
                expression { return env.MIGRATIE_EIGEN_REPO?.trim() as boolean }
            }
            steps {
                script {
                    def opties = [url: env.MIGRATIE_EIGEN_REPO, branch: env.MIGRATIE_EIGEN_BRANCH ?: 'main']
                    if (env.MIGRATIE_EIGEN_CREDENTIALS) {
                        opties.credentialsId = env.MIGRATIE_EIGEN_CREDENTIALS
                    }
                    dir('eigen') {
                        git(opties)
                    }
                    if (fileExists('eigen/migraties')) {
                        env.MIGRATIES_MAP = "${env.WORKSPACE}/eigen/migraties"
                    }
                    if (fileExists('eigen/recepten/pom.xml')) {
                        env.RECEPTEN_MAP = "${env.WORKSPACE}/eigen/recepten"
                    }
                    echo "eigen migraties: ${env.MIGRATIES_MAP ?: '-'}, eigen recepten: ${env.RECEPTEN_MAP ?: '-'}"
                }
            }
        }

        stage('Gereedschap') {
            steps {
                sh 'jenkins/gereedschap.sh "$GEREEDSCHAP"'
            }
        }

        stage('Migratie kiezen') {
            steps {
                script {
                    def gepland = !currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause').isEmpty()
                    def gekozen = params.MIGRATIE?.trim()
                    if (gepland || !gekozen) {
                        if (!env.MIGRATIE_SJABLOON?.trim()) {
                            error(gepland ? 'Een geplande build heeft MIGRATIE_SJABLOON nodig'
                                          : 'Vul MIGRATIE in (naam of pad), of zet MIGRATIE_SJABLOON voor deze job')
                        }
                        // Een ronde van het sjabloon: een kopie met de ronde in de naam, en zonder
                        // BRANCH, zodat elke ronde een eigen branch krijgt.
                        withEnv(["RONDE_FORMAAT=${env.MIGRATIE_RONDE ?: '%G-w%V'}"]) {
                            sh '''
                                bron="$(bash -c '. lib/migratie.sh; laad_migratie "$1" >/dev/null && echo "$MIGRATIE_BESTAND"' _ "$MIGRATIE_SJABLOON")"
                                naam="$(basename "$bron" .env)-$(date +"$RONDE_FORMAAT")"
                                {
                                    echo "# Ronde van $(basename "$bron"), aangemaakt door Jenkins."
                                    grep -v '^BRANCH=' "$bron"
                                } > "migraties/$naam.env"
                                echo "$naam" > .migratie-naam
                            '''
                        }
                        env.MIGRATIE_NAAM = readFile('.migratie-naam').trim()
                        env.GO_VLAG = (gepland || params.GO) ? '--go' : ''
                    } else {
                        env.MIGRATIE_NAAM = gekozen
                        env.GO_VLAG = params.GO ? '--go' : ''
                    }
                    if (!gepland && params.GO && params.ZONDER_VERIFY) {
                        error('ZONDER_VERIFY mag alleen bij een dry-run')
                    }
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.MIGRATIE_NAAM}" + (env.GO_VLAG ? '' : ' (dry-run)')
                }
            }
        }

        stage('Migratie') {
            steps {
                script {
                    def credentials = [string(credentialsId: env.MIGRATIE_GITLAB_CREDENTIALS, variable: 'GITLAB_TOKEN')]
                    if (env.MIGRATIE_TEMPLATE_CREDENTIALS) {
                        credentials << gitUsernamePassword(credentialsId: env.MIGRATIE_TEMPLATE_CREDENTIALS, gitToolName: 'Default')
                    }

                    def pad = ["${env.GEREEDSCHAP}/bin", "${env.GEREEDSCHAP}/venv/bin"]
                    def omgeving = ["CRUFT_PYTHON=${env.GEREEDSCHAP}/venv/bin/python"]
                    if (env.MIGRATIE_JDK) {
                        def jdk = tool(name: env.MIGRATIE_JDK, type: 'jdk')
                        pad << "${jdk}/bin"
                        omgeving << "JAVA_HOME=${jdk}"
                    }
                    if (env.MIGRATIE_MAVEN) {
                        pad << "${tool(name: env.MIGRATIE_MAVEN, type: 'maven')}/bin"
                    }
                    omgeving << "PATH+MIGRATIE=${pad.join(':')}"

                    def naam = env.MIGRATIE_GIT_NAAM ?: 'migratie-tools'
                    def email = env.MIGRATIE_GIT_EMAIL ?: 'migratie-tools@localhost'
                    omgeving += ["GIT_AUTHOR_NAME=${naam}", "GIT_COMMITTER_NAME=${naam}",
                                 "GIT_AUTHOR_EMAIL=${email}", "GIT_COMMITTER_EMAIL=${email}"]

                    withCredentials(credentials) {
                        withEnv(omgeving) {
                            sh '''
                                rm -rf runs
                                set -- "$MIGRATIE_NAAM" $GO_VLAG
                                [ -z "$REPO_INCLUDE" ] || set -- "$@" --repo-include "$REPO_INCLUDE"
                                [ "$ZONDER_VERIFY" != true ] || set -- "$@" --zonder-verify
                                java -version 2>&1 | head -1
                                ./run.sh "$@"
                            '''
                        }
                    }
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
        unstable {
            // Plek voor een eigen melding, bv. naar een chatkanaal met de werklijst.
            echo 'Er is handwerk nodig; de werklijst staat in de artefacten (runs/*/resultaten.tsv).'
        }
        failure {
            // Plek voor een eigen melding bij een mislukte run.
            echo 'De run is mislukt; zie de console-uitvoer.'
        }
        cleanup {
            deleteDir()   // de tools staan buiten de workspace en blijven bewaard
        }
    }
}
