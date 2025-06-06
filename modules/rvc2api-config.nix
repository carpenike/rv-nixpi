{ config, pkgs, lib, rvc2api, ... }:

{
  # Enable and configure rvc2api service
  rvc2api = {
    enable = true;
    
    # Use the package from the flake input (this is the default, but explicit is good)
    # package = inputs.rvc2api.packages.${pkgs.system}.rvc2api; # No need to set this as it's the default
    
    settings = {
      # App metadata
      appName = "rvc2api";
      appVersion = "0.0.0";
      appDescription = "API for RV-C CANbus";
      appTitle = "RV-C API";
      
      # Server settings (new structured format)
      server = {
        host = "0.0.0.0";  # Bind to all interfaces
        port = 8000;
        workers = 1;
        reload = false;
        debug = false;
        rootPath = "";
        accessLog = true;
        keepAliveTimeout = 5;
        timeoutGracefulShutdown = 30;
        timeoutNotify = 30;
        workerClass = "uvicorn.workers.UvicornWorker";
        workerConnections = 1000;
        serverHeader = true;
        dateHeader = true;
      };
      
      # Logging settings (new structured format)
      logging = {
        level = "INFO";
        format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s";
        logToFile = false;
        maxFileSize = 10485760;  # 10MB
        backupCount = 5;
      };
      
      # CORS settings
      cors = {
        allowedOrigins = [ "*" ];
        allowedCredentials = true;
        allowedMethods = [ "*" ];
        allowedHeaders = [ "*" ];
      };
      
      # CANbus settings
      canbus = {
        channels = [ "can0" "can1" ];
        bustype = "socketcan";
        bitrate = 500000;
      };
      
      # Feature flags (new structured format)
      features = {
        enableMaintenanceTracking = false;
        enableNotifications = false;
        enableUptimerobot = false;
        enablePushover = false;
        enableVectorSearch = true;
        enableApiDocs = true;
        enableMetrics = true;
      };
      
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
      
      # Controller settings
      controllerSourceAddr = "0xF9";
      
      # RVC configuration
      modelSelector = "2021_Entegra_Aspire_44R";
      
      # Path settings - point to files in /etc/nixos/files/
      # rvcSpecPath = "/etc/nixos/files/rvc.json";
      # deviceMappingPath = "/etc/nixos/files/device_mapping.yml";
      
      # GitHub update checking
      githubUpdateRepo = "carpenike/rvc2api";
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
    enable  = true;
    #package = pkgs.caddy;
    email   = "ryan@ryanholt.net";
    virtualHosts."rvc.holtel.io".extraConfig = ''
      tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        resolvers 1.1.1.1
      }
      reverse_proxy http://localhost:8000
      '';
};
systemd.services.caddy.serviceConfig.EnvironmentFile = "/run/secrets/caddy_cloudflare_env";
# Open port 8000 for direct backend access (if needed)
networking.firewall.allowedTCPPorts = [ 8000 443 ];
}
