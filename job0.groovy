pipelineJob('job1') {
  logRotator(120, -1, 1, -1)
  authenticationToken('secret')
  definition {
    cps {
      script("""\
        pipeline {
          agent any
          parameters {
              string(name: 'PARAM_URL', defaultValue: 'https://mail.ru', description: 'URL for test', trim: true)
              string(name: 'PARAM_EMAIL', defaultValue: 'yakovlev.sergey@sciencecraft.ru', description: 'Email for send test result', trim: true)
          }
          options {
            timestamps()
            ansiColor('xterm')
            timeout(time: 10, unit: 'MINUTES')
          }
          stages {
            stage ('Clone sources') {
              steps {
                sh '''rm -rf jenkins-test-script
                git clone 'https://github.com/MonsterRoot/jenkins-test-script.git'
                chmod +x jenkins-test-script/test-url.sh'''
              }
            }
            stage ('run') {
              steps {
                script{
                    BUILD_RESULT = sh returnStdout: true, script:"jenkins-test-script/test-url.sh \$PARAM_URL"
                }
              }
            }
            stage ('send result') {
              steps {
                mail (body:
                "\$BUILD_RESULT",
                subject: 'Pipeline build result',
                to: "\$PARAM_EMAIL")
              }
            }
          }
        }""".stripIndent())
      sandbox()
    }
  }
}