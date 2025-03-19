FROM python:3.9-slim

WORKDIR /app

# Upgrade pip
RUN pip install --upgrade pip

# Copy requirements first to leverage Docker caching
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create a data directory for storing user files
RUN mkdir -p data && chmod 777 data

# Install additional security packages
RUN pip install pyopenssl flask-talisman flask-cors

# Environment variables
ENV FLASK_ENV=production
ENV PORT=8080

# Expose the port
EXPOSE 8080

# Set non-root user for better security
RUN useradd -m appuser
RUN chown -R appuser:appuser /app
USER appuser

# Run the application with Gunicorn
CMD exec gunicorn --bind :$PORT --workers 2 --threads 8 --timeout 0 app:app