# gestion-compte-contrat
Dépôt du contrat de l'API Gestion Comptes

## vérification du contrat
Pour vérifier le contrat, vous pouvez utiliser la commande suivante :

```bash
redocly lint ./gestion-compte-contrat.yml
```

Si `redocly` n'est pas installé, la tâche Gradle `checkContract` sera ignorée.

## projet Gradle
Ce dépôt peut être utilisé comme projet Gradle pour valider le contrat, tester les stubs et générer un JAR.

Commandes utiles :

```bash
./gradlew check
./gradlew jar
```

## publication pour les consommateurs
Le workflow GitHub Actions publie aussi le contrat comme dépendance Maven sur GitHub Packages.

Coordonnées Maven :

```text
groupId: com.awa.centrale
artifactId: gestion-compte-contrat
version: 1.0.0
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
