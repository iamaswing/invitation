FROM nginx:latest
# Copy the local file into the Nginx directory inside the image
COPY index.html /usr/share/nginx/html/index.html