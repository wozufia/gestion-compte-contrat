# gestion-compte-contrat
Dépôt du contrat de l'API Gestion Comptes

## vérification du contrat
Pour vérifier le contrat, vous pouvez utiliser la commande suivante :

```bash
redocly lint ./gestion-compte-contrat.yml
```

## tester les stubs WireMock
Des stubs WireMock sont disponibles dans `stubs/`.

Lancer WireMock :

```bash
docker compose -f docker-compose.wiremock.yml up
```

Tester `POST /auth/login` :

```bash
curl -i -X POST 'http://localhost:8081/api/comptes/v1/auth/login' \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@example.com","motDePasse":"Str0ng@Pass!"}'
```

Lancer les requêtes de test pour tous les endpoints :

```bash
bash stubs/test-requests.sh
```
