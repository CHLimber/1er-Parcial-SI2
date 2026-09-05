FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# Railway inyecta las variables del servicio como build args cuando coinciden con un ARG
# declarado aca -- definir API_URL en las variables del servicio frontend con la URL publica
# del backend (p.ej. https://fashionstore-backend-production.up.railway.app).
ARG API_URL=http://localhost:8080
RUN sed -i "s#__API_URL__#${API_URL}#" src/environments/environment.ts

RUN npm run build

FROM nginx:1.27-alpine

COPY --from=build /app/dist/fashionstore-frontend/browser /usr/share/nginx/html
COPY default.conf.template /etc/nginx/templates/default.conf.template

# Fallback para correr el contenedor fuera de Railway (que inyecta PORT en runtime).
ENV PORT=8080
EXPOSE 8080
