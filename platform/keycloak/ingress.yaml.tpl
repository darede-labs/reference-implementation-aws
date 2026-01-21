apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
  annotations:
    external-dns.alpha.kubernetes.io/hostname: {{ keycloak_subdomain }}.{{ domain }}
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: {{ keycloak_subdomain }}.{{ domain }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak
                port:
                  number: 8080
