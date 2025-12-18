# Step 1: Build the React App
FROM node:18-alpine as build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./

# CRITICAL: Build Arguments for BOTH APIs
ARG REACT_APP_API_BASE_URL
ARG REACT_APP_SUPERSET_BASE_URL

ENV REACT_APP_API_BASE_URL=$REACT_APP_API_BASE_URL
ENV REACT_APP_SUPERSET_BASE_URL=$REACT_APP_SUPERSET_BASE_URL

RUN npm run build

# Step 2: Serve with Nginx
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
# COPY CUSTOM NGINX CONFIG
# COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
RUN rm /etc/nginx/conf.d/default.conf
# Configure Nginx to listen on Port 3000
# RUN sed -i 's/listen       80;/listen       3000;/' /etc/nginx/conf.d/default.conf
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]