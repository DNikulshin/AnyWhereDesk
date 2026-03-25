{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = with pkgs; [
    docker
    docker-compose
    postgresql_15
    curl
    jq
    gnumake            # было make → исправлено на gnumake
    firebase-tools
    bashInteractive
  ];

  services.docker.enable = true;

  env = {
    COMPOSE_PROJECT_NAME = "anywheredesk";
    GUACAMOLE_PORT = "8080";
    POSTGRES_PORT = "5432";
  };

  idx = {
    extensions = [
      "google.gemini-cli-vscode-ide-companion"
      "ms-azuretools.vscode-docker"
      "redhat.vscode-yaml"
    ];

    previews = {
      enable = true;
      previews = {
        web = {
          command = [
            "sh"
            "-c"
            "echo 'AnywhereDesk is starting. Guacamole will be at http://localhost:8080' && sleep infinity"
          ];
          manager = "web";
        };
      };
    };

    workspace = {
      onCreate = {
        mkdir-init = "mkdir -p init";
        generate-schema = ''
          echo "Waiting for Docker to be ready..."
          while ! docker info >/dev/null 2>&1; do sleep 1; done
          echo "Generating Guacamole database schema..."
          docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > init/initdb.sql
          echo "✅ Schema saved to init/initdb.sql"
        '';
        start-stack = ''
          echo "Starting AnywhereDesk services..."
          docker-compose up -d
          echo "✅ Services started. Guacamole available at http://localhost:8080"
        '';
      };
      onStart = {
        check-stack = ''
          echo "Checking AnywhereDesk containers..."
          docker-compose ps
        '';
      };
    };
  };
}