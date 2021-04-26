kubectl create secret generic ordspassword --type=string --from-literal=password=MYCLEARTEXTPASSWORD

kubectl create secret generic oke-registry-secret --from-file=.dockerconfigjson=.\config.json --type=kubernetes.io/dockerconfigjson

kubectl apply -f ords_novolume.yaml

