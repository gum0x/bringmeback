# Use a minimal Nginx base image
FROM nginx:latest

# Copy the Flutter web build output to the Nginx default web root
COPY build/web/ /usr/share/nginx/html

# Expose the default Nginx port
EXPOSE 80

# Start the Nginx web server
CMD ["nginx", "-g", "daemon off;"]
