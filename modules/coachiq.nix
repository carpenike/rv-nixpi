{ config, pkgs, lib, coachiq, ... }:

{
  # Enable and configure coachiq service
  coachiq = {
    enable = true;
    
    # Use the package from the flake input (this is the default, but explicit is good)
    # package = inputs.coachiq.packages.${pkgs.system}.coachiq; # No need to set this as it's the default

    settings = {
      # App metadata
      # appName = "CoachIQ";
      # appVersion = "0.0.0";
      # appDescription = "API for CoachIQ";
      # appTitle = "CoachIQ API";
      
      # Server settings (new structured format)
      server = {
        host = "0.0.0.0";  # Bind to all interfaces
        port = 8000;
        # workers = 1;
        # reload = false;
        # debug = false;
        # rootPath = "";
        # accessLog = true;
        # keepAliveTimeout = 5;
        # timeoutGracefulShutdown = 30;
        # timeoutNotify = 30;
        # workerClass = "uvicorn.workers.UvicornWorker";
        # workerConnections = 1000;
        # serverHeader = true;
        # dateHeader = true;
      };
      
      # Logging settings (new structured format)
      # logging = {
      #   level = "INFO";
      #   format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s";
      #   logToFile = false;
      #   maxFileSize = 10485760;  # 10MB
      #   backupCount = 5;
      # };
      
      # CORS settings
      # cors = {
      #   allowedOrigins = [ "*" ];
      #   allowedCredentials = true;
      #   allowedMethods = [ "*" ];
      #   allowedHeaders = [ "*" ];
      # };
      
      # CANbus settings
      canbus = {
        channels = [ "can0" "can1" ];
        bustype = "socketcan";
        bitrate = 500000;

        interfaceMappings = {
          house = "can1";                # House systems -> can1
          chassis = "can0";              # Chassis systems -> can0
        };
      };
      
      # Feature flags (new structured format)
      # features = {
      #   enableMaintenanceTracking = false;
      #   enableNotifications = false;
      #   enableUptimerobot = false;
      #   enablePushover = false;
      #   enableVectorSearch = true;
      #   enableApiDocs = true;
      #   enableMetrics = true;
      # };
      
      # Notification settings (new structured format)
      notifications = {
        # Pushover settings (when features.enablePushover = true)
        # pushoverUserKey = "your-user-key";
        # pushoverApiToken = "your-api-token";
        # pushoverDevice = null;
        # pushoverPriority = null;
        
        # UptimeRobot settings (when features.enableUptimerobot = true)
        # uptimerobotApiKey = "your-api-key";
      };

      security = {
        tlsTerminationIsExternal = true;
      };
      
      # Controller settings
      controllerSourceAddr = "0xF9";
      
      # RVC configuration
      rvcCoachModel = "2021_Entegra_Aspire_44R";
      
      # Path settings - point to files in /etc/nixos/files/
      # rvcSpecPath = "/etc/nixos/files/rvc.json";
      # deviceMappingPath = "/etc/nixos/files/device_mapping.yml";
      
      # GitHub update checking
      githubUpdateRepo = "carpenike/coachiq";
    };
  };

  # Enable complementary RVC services
  services.rvc = {
    console.enable = true;
    debugTools.enable = true;
  };

  # Configure Cloudflared tunnel
  services.rvcCloudflared = {
    enable = true;
    hostname = "rvc.holtel.io";
    service = "https://localhost";
  };

  # Configure Caddy to serve React frontend and proxy API
  services.caddy = {
    enable = true;
    email = "ryan@ryanholt.net";
    virtualHosts."rvc.holtel.io".extraConfig = ''
      tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        resolvers 1.1.1.1
      }

      # Health endpoints - proxy to FastAPI backend
      handle /health {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /healthz {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /readyz {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /metrics {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      # API routes - proxy to FastAPI backend
      handle /api/* {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      # WebSocket endpoints - proxy to FastAPI backend
      handle /ws/* {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /ws {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      # FastAPI docs and schema - proxy to FastAPI backend
      handle /docs* {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /redoc* {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      handle /openapi.json {
        reverse_proxy http://localhost:8000
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
      }

      # Serve static frontend files for everything else
      handle {
        root * ${coachiq.packages.${pkgs.system}.frontend}
        try_files {path} /index.html
        file_server
      }

      header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options nosniff
          X-Frame-Options DENY
          X-XSS-Protection "1; mode=block"
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"
      }
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "coachiq-migrate" ''
      set -e
      echo "Running CoachIQ database migrations..."

      # Set environment to match your service
      export COACHIQ_DATABASE__SQLITE_PATH="/var/lib/coachiq/coachiq.db"
      export COACHIQ_PERSISTENCE__ENABLED=true
      export COACHIQ_PERSISTENCE__DATA_DIR="/var/lib/coachiq"

      # Run migrations using the packaged alembic
      cd ${coachiq.packages.${pkgs.system}.coachiq}/lib/python*/site-packages
      ${coachiq.packages.${pkgs.system}.coachiq}/bin/alembic upgrade head

      echo "Migrations completed successfully"
    '')
  ];

  systemd.services.caddy.serviceConfig.EnvironmentFile = "/run/secrets/caddy_cloudflare_env";
  # Open port 8000 for direct backend access (if needed)
  networking.firewall.allowedTCPPorts = [ 8000 443 ];
}
