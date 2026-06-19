output "node_a_public_ip" { value = aws_instance.node[0].public_ip }
output "node_b_public_ip" { value = aws_instance.node[1].public_ip }
output "node_a_private_ip" { value = aws_instance.node[0].private_ip }
output "node_b_private_ip" { value = aws_instance.node[1].private_ip }

# Primary ENI ids — feed these to scripts/enable-ena-express.sh
output "node_a_eni_id" { value = aws_instance.node[0].primary_network_interface_id }
output "node_b_eni_id" { value = aws_instance.node[1].primary_network_interface_id }

output "ena_express_cmd" {
  value = "./scripts/enable-ena-express.sh on ${aws_instance.node[0].primary_network_interface_id} ${aws_instance.node[1].primary_network_interface_id}"
}
