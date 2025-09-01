# ELK Stack with Security

This directory contains a complete ELK (Elasticsearch, Logstash, Kibana) stack deployment with security enabled.

## Components

- **Elasticsearch**: Search and analytics engine with SSL/TLS encryption
- **Kibana**: Data visualization and exploration tool
- **Logstash**: Data processing pipeline
- **Setup Container**: Automatically configures certificates and security

## Features

- ✅ SSL/TLS encryption between all components
- ✅ User authentication and authorization
- ✅ Self-signed certificates automatically generated
- ✅ Persistent data storage
- ✅ Health checks for all services
- ✅ Memory limits configured

## Quick Start

1. **Start the stack**:
   ```bash
   ./start-elk.sh
   ```

2. **Access the services**:
   - Elasticsearch: https://localhost:9200
   - Kibana: http://localhost:5601

3. **Default Credentials**:
   - Elasticsearch: `elastic` / `ElasticPassword123`
   - Kibana: `kibana_system` / `KibanaPassword123`

## Data Storage

All data is persisted in the `./data/elk/` directory:
- `certs/`: SSL certificates
- `elasticsearch/`: Elasticsearch indices and data
- `kibana/`: Kibana configuration and saved objects
- `logstash/`: Logstash data and plugins
- `logstash_ingest_data/`: Directory for data files to be ingested

## Ports

- **9200**: Elasticsearch HTTP API (HTTPS)
- **5601**: Kibana web interface (HTTP)
- **5044**: Logstash Beats input
- **50000**: Logstash TCP/UDP input
- **9600**: Logstash monitoring API

## Environment Variables

All ELK credentials are stored in the local `.env` file in this directory:
- `ELASTIC_VERSION`: ELK stack version
- `ELASTIC_PASSWORD`: Elasticsearch superuser password
- `KIBANA_PASSWORD`: Kibana system user password
- Additional user passwords for various internal services

## Management Commands

```bash
# Start services (uses local .env automatically)
docker-compose up -d

# View logs
docker-compose logs -f [service_name]

# Check status
docker-compose ps

# Stop services
docker-compose down

# Remove all data (destructive)
docker-compose down -v
sudo rm -rf ./data/elk/
```

## Security Notes

- All communication between services uses SSL/TLS
- Certificates are automatically generated on first startup
- Default passwords should be changed in production
- Network is isolated with a dedicated Docker network
- ELK credentials are isolated in this directory's .env file

## Troubleshooting

1. **Permission Issues**: Run the start script which sets proper permissions
2. **Memory Issues**: Ensure Docker has at least 4GB RAM allocated
3. **Certificate Issues**: Delete `./data/elk/certs/` and restart to regenerate
4. **Connection Issues**: Wait for all health checks to pass (can take 2-3 minutes)

## Monitoring

Each service has health checks configured. You can monitor the stack health with:
```bash
docker-compose ps
```

All services should show "healthy" status when fully operational.
