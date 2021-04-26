Basierend auf den Docker Build Skripten von Oracle (github.com/oracle/docker-images) habe ich das Skript für OracleRestDataServices ein wenig angepaßt und für Autonomous-Wallets tauglich gemacht. Daher sind die groben Schritte:

<b>1) Docker Image für Java erzeugen</b><br>
server-jre-8u291-linux.x64.tar.gz herunterladen von oracle: (Patchlevel egal, Dateiname server-jre-8*.tar.gz)<br>
Java SE - Downloads | Oracle Technology Network | Oracle Deutschland(Server JRE download)<br>
<br>
Kopieren in das Verzeichnis docker-images/OracleJava/8<br>
Ausführen von docker-images/OracleJava/8/build.sh<br>
<br>
<b>2) Docker Image für ORDS erzeugen (verwendet/basiert auf dem Java Image)</b><br>
Oracle REST Data Services 20.4.3 herunterladen von oracle: (Patchlevel egal, Dateiname ords*zip)<br>
Oracle REST Data Services Download<br>
Autonomus DB Wallet herunterladen von Oracle Cloud (z.B. Klick auf Autonomous DB -> Ihre Datenbank -> Button "DB Connection" -> Button "Download Wallet". Die Wallet Datei muß mit dem Namen "Wallet_*") beginnen, mit großem W. Falls nicht, bitte einfach entsprechend umbenennen.<br>
<br>
Kopieren beider Dateien (ords*zip und Wallet*zip) nach docker-images/OracleRestDataServices/dockerfiles<br>
<br>
Aufruf von docker-images/OracleRestDataServices/dockerfiles/buildDockerImage.sh<br>
<br>
<br>
<b>3) Beide Docker images nach Frankfurt hochladen</b><br>
docker tag oracle/serverjre:8 fra.ocir.io/<tenant-name>/<repo-name>/oracle/serverjre:8<br>
docker tag oracle/restdataservices:20.4.3 fra.ocir.io/<tenant-name>/<repo-name>/oracle/restdataservices:20.4.3<br>
docker login fra.ocir.io<br>
Benutzername: <tenant-name>/<mail-adresse><br>
Passwort: AUTH TOKEN erzeugt in Cloud UI (z.B: Klick auf eigenen Benutzer -> Settings -> Auth Token)<br>
<br>
docker push fra.ocir.io/<tenant-name>/<repo-name>/oracle/serverjre:8<br>
docker push fra.ocir.io/<tenant-name>/<repo-name>/oracle/restdataservices:20.4.3<br>
<br>
<b>4) Kubernetes Anwendung einrichten</b><br>
<b>4.1) Erzeugen eines Datenbank-Benutzers mit ORDS Berechtigung (parallel zu ORDS_PUBLIC_USER, z.B. ORDS_CUSTOM) via "admin" Benutzer:</b><br>
CREATE USER "ORDS_CUSTOM" IDENTIFIED BY "password";<br>
GRANT "CONNECT" TO "ORDS_CUSTOM";<br>
BEGIN<br>
     ORDS_ADMIN.PROVISION_RUNTIME_ROLE(<br>
         p_user => 'ORDS_CUSTOM',<br>
         p_proxy_enabled_schemas => TRUE);<br>
END;<br>
/<br>
<br>
<b>4.2) Kubernetes "Secrets" erzeugen für den ORDS login und für den Download der Docker images von fra.ocir.io.</b><br>
<br>
Der eben neu angelegte DB Benutzer (z.B. ORDS_CUSTOM) erhielt auch ein Kennwort. Dieses bitte hier verwenden:<br>
kubectl create secret generic ordspassword --type=string --from-literal=password=MYCLEARTEXTPASSWORD<br>
<br>
Das Secret für den Docker login kann auf mehrere Arten erzeugt werden. Die einfachste ist, <br>
die bestehende docker Konfiguration zu verwenden ($HOME/.docker/config.json):<br>
<br>
kubectl create secret generic oke-registry-secret --from-file=.dockerconfigjson=.\config.json --type=kubernetes.io/dockerconfigjson<br>
<br>
<b>4.3) Anpassen der Datei ords_novolume.yaml</b><br>
In der Datei docker-images/ords_novolume.yaml ist anzupassen:<br>
Der Name des Docker Images, d.h. Tenant Name und Name des Repositories:<br>

    spec:
      containers:
        - name: ordscontainer
          image: ams.ocir.io/tenantname/reponame/oracle/restdataservices:20.4.3

DB Service und Benutzername des eben erzeugten Datenbank-Users ("ORDS_CUSTOM").<br>
Der Eintrag ORACLE_PWD bzw. "dummy" ist beizubehalten ! Der Eintrag ORDS_PWD wird dynamisch aus dem eben erzeugten Secret ausgelesen.<br>

          - name: ORACLE_USER
            value: "ORDS_CUSTOM"
          - name: ORACLE_SERVICE
            value: "repodb_medium"
          - name: CONTEXT_ROOT
            value: "ords"
          - name: ORACLE_PWD
            value: "dummy"
          - name: ORDS_PWD
            valueFrom:
              secretKeyRef:
                name: ordspassword
                key: password

<b>4.4) Einrichten der Anwendung</b><br>
Ausführen des Skriptes "ords_novolumes.yaml" mit<br>
kubectl apply -f ords_novolumes.yaml<br>
<br>
Das Skript legt ein Deployment mit zwei ORDS-Containern ("Replica: 2" im yaml-File) an<br>
sowie einen Netzwerk-Service mit einem LBaaS LoadBalancer davor ("type: LoadBalancer" im yaml-File).<br>
<br>
<b>5) Prüfung ob alles geklappt hat</b><br>
Die Einrichtung erfolgte ohne Angabe von Namespaces. D.h. alle Secrets, Services und das Deployment landen aktuell im "default" namespace.<br>
<br>
kubectl get pods (Zwei Pods mit Namen ordscontainer* ?)<br>
kubectl get services (Public IP des Loadbalancers vorhanden? Dauert ein Weilchen, steht eine Weile auf "Pending")<br>
kubectl logs <pod-name> (Java Stack Trace bei erfolglosem DB login oder nicht lesbarem Wallet file)<br>
<br>
Falls kein Pod angelegt werden kann, z.B. Status nicht "RUNNING" oder bleibt ewig bei "PENDING":<br>
kubectl edit pod <pod-name><br>

Das nun einsehbare YAML File enthält ziemlich am Ende einige Kubernetes-Fehlermeldungen wie z.B.<br>
kann das Docker Image nicht herunterladen, nicht genügend Memory , ....<br>
<br>
Die ORDS Container erzeugen ihre Konfiguration beim ersten start selbst neu.<br>
Eine Persistierung der Konfiguration in einem separate Volume ist daher eigentlich nicht nötig.<br>
Es gibt zum Test ein weiteres YAML File, das die Konfiguration in einem Volume ablegt, jedoch<br>
auf einem lokalen Filesystem, d.h. jeder Worker Node bekommt seine eigene Konfiguration.<br>
Ein Shared Volume über NFS wäre viel schöner, das kann ich bei Bedarf gerne nachreichen.<br>
