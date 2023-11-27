Данный репозиторий предназначен для развертывания kubernetes managed cluster и jenkins внутри него.

Чтоб развернуть кластер необходимо выполнить без параметров скрипт install.sh
```shell
./install.sh
```
Ключевые моменты скрипта:
```shell
TF_IN_AUTOMATION=1 terraform init -upgrade #Инициализация локального terraform
TF_IN_AUTOMATION=1 terraform apply -auto-approve #Непосредственно разворот инфраструктуры в Yandex Cloud
terraform output kubeconfig > /home/$USER/.kube/config #выгружает данные для подключения к получившемуся кластеру kubernetes
kubectl apply -f ClusterIssuer.yaml #Создаёт необходимые для возможности подключения к jenkins из вне ingress

```
Файл содержащий о настройках kubernetes
`main.tf`
Файл с настройками jenkins
`helm_jenkins.tf`

Пароль почтового ящика для отправки почты из jenkins необходимо разместить в файле
`.email_password`
Пароль для пользователя admin jenkins в файле
`.password`

Файлы с паролями добавлены в .gitignore

Единственный job, который автоматически добавляется в jenkins хранит свой pipeline в файле
`job0.groovy`
В качестве параметров задание принимает URL и Адрес электронной почты, для отправки на него результатов выполнения

Для уничтожения кластера необходимо использовать команду
`./destroy.sh`
