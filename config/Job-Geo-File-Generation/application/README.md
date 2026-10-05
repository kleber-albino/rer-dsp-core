# Geo-file job — Spring configuration

Spring Boot settings for `dsp-job-geo-file-generation` live in the job repository:

`src/main/resources/application.properties`

Docker Compose and `.env` override datasources, object storage, and the path to
`downloadThemesConfig.json` (same pattern as `dsp-backend`).
