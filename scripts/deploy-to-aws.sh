#!/bin/bash

# ============================================================
# VittaGems AWS Deployment Script (Single Node / Minimum Spec)
# This script copies the local project to the AWS EC2 instance
# and executes the deployment automatically.
# ============================================================

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${GREEN}[STEP]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --------------------------------------------------
# 1. Parse Arguments
# --------------------------------------------------
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <aws-ip> <path-to-pem-key> [aws-user]"
    echo "Example: $0 54.123.45.67 ~/.ssh/my-key.pem ubuntu"
    exit 1
fi

AWS_IP=$1
PEM_KEY=$2
AWS_USER=${3:-ubuntu}

# Check if PEM key exists
if [ ! -f "$PEM_KEY" ]; then
    print_error "PEM key file not found at: $PEM_KEY"
    exit 1
fi

# --------------------------------------------------
# 2. Check Connection
# --------------------------------------------------
print_step "Checking SSH connection to ${AWS_USER}@${AWS_IP}..."
if ! ssh -i "$PEM_KEY" -o StrictHostKeyChecking=no -q "$AWS_USER@$AWS_IP" exit; then
    print_error "Failed to connect to AWS instance. Check IP, key, and Security Groups."
    exit 1
fi

# --------------------------------------------------
# 3. Rsync Project to AWS
# --------------------------------------------------
print_step "Syncing VittaGems project to AWS..."
rsync -avz --exclude 'node_modules' --exclude '.git' --exclude 'network' --exclude 'artifacts' --exclude 'cache' \
  -e "ssh -i $PEM_KEY -o StrictHostKeyChecking=no" \
  ./ "$AWS_USER@$AWS_IP:~/vittagems-blockchain/"

# --------------------------------------------------
# 4. Remote Execution: Setup & Deploy
# --------------------------------------------------
print_step "Running setup and deployment on AWS..."
ssh -i "$PEM_KEY" -o StrictHostKeyChecking=no "$AWS_USER@$AWS_IP" << 'EOF'
  set -e
  
  # Ensure NVM is loaded if it exists
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  cd ~/vittagems-blockchain

  # 1. Run the environment setup script (installs Docker, Go)
  # We pipe 'y' to auto-accept reinstall prompts if any
  echo "y" | bash vittagems-env-setup.sh || true

  # 2. Install Node.js if not present
  if ! command -v node &> /dev/null; then
    echo "Installing Node.js 20..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
  fi

  # 3. Install project dependencies
  echo "Installing npm dependencies..."
  npm install

  # 4. Deploy the network (Quorum + Monitoring)
  echo "Deploying Quorum network..."
  sudo bash deploy-network.sh --reset --aws-cloudwatch
  
  # 5. Compile and deploy contracts to the new AWS network
  echo "Compiling and deploying smart contracts..."
  npm run compile
  npm run deploy:local
  npx hardhat run scripts/deploy/deploy-permissioning.js --network quorum_local

  echo -e "\n\033[0;32m[DONE]\033[0m VittaGems AWS Deployment Complete!"
  echo "You can check status with: cd ~/vittagems-blockchain && npm run network:status"
EOF

print_step "AWS Deployment Finished Successfully."
echo "Access your RPC endpoint at: http://${AWS_IP}:8545"
echo "Access Grafana at: http://${AWS_IP}:3000 (admin / vittagems)"
