# AWS Free Tier Setup Guide

Follow these steps to deploy your VPN server for free.

## 1. Launch EC2 Instance
- **Region**: Recommend `us-east-1` (Virginia) or `us-east-2` (Ohio).
- **AMI**: Amazon Linux 2023 (Free Tier Eligible).
- **Instance Type**: `t3.micro` (Note: `t2.micro` is the older free tier).
- **Key Pair**: Create a new one (.pem) to SSH into the server from Windows.

## 2. Security Group Configuration
| Protocol | Port | Source | Description |
|---|---|---|---|
| **SSH** | 22 | My IP | For your access only |
| **UDP** | 51820 | 0.0.0.0/0 | Standard WireGuard Tunnel |
| **TCP** | 443 | 0.0.0.0/0 | WebSocket Fallback Relay |

## 3. Server Deployment
1. Connect via SSH: `ssh -i your-key.pem ec2-user@<AWS-PUBLIC-IP>`
2. Copy the `setup_aws_server.sh` script to the server.
3. Run the script:
   ```bash
   chmod +x setup_aws_server.sh
   ./setup_aws_server.sh
   ```
4. Copy the output **Client Configuration** into your Flutter app.

## 4. Cost Optimization (Essential!)
> [!WARNING]
> AWS Free Tier has limitations. To avoid charges:
> 1. **Data Transfer**: Free Tier typically allows 100GB/month of egress data. Monitor this in the Billing Dashboard.
> 2. **Elastic IP**: Only use one. If you stop the instance, release the Elastic IP or you will be charged per hour.
> 3. **Stopping vs Terminating**: Stop the instance when not testing to save on "Public IPv4 address" charges (AWS now charges $0.005/hr for all public IPv4s, approx $3.60/mo). To stay 100% free, **Terminate** the instance when finished with the project.
