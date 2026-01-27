sudo snap install kubectl --classic
kind create cluster --config kind-config.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type='merge' -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","node-role.kubernetes.io/control-plane":""}}}}}'
kubectl get nodes
kubectl -n ingress-nginx get pods
kubectl apply -f sample-app.yaml
kubectl apply -f robot-shop-ingress.yaml