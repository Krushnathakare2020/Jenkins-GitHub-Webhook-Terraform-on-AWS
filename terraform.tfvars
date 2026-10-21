aws_region          = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
instance_type       = "t3.micro"

# Replace with your existing EC2 key pair name
key_name = "my_instance_key"

# Replace with your actual public IP address
# Example format: "203.0.113.10/32"
ssh_cidr = "49.36.44.146/32"
