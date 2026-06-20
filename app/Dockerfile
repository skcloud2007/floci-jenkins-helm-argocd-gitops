FROM node:22-alpine AS dependencies

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

FROM node:22-alpine AS runtime

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

RUN addgroup -S appgroup -g 10001 \
  && adduser -S appuser -G appgroup -u 10001

COPY --from=dependencies /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER 10001:10001

EXPOSE 3000

CMD ["npm", "start"]
