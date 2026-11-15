output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zones the subnets are spread across."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnets (load balancers, NAT gateways)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets (EKS nodes and pods, EFS mount targets)."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs. Known at plan time, so safe to use in for_each."
  value       = local.private_subnet_cidrs
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways: all outbound traffic from pods leaves from these. Allow-list them in MongoDB Atlas and with the payment provider."
  value       = aws_eip.nat[*].public_ip
}
