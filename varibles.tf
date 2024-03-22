variable "server_port" {
  description = "The port for HTTP requests"
  type = number
  default = 8080
  }
variable "ssh_port" {
  description = "ssh"
  type = number
  default = 22
  }
  
variable "destination_port" {
  description = "Destination prot of LB"
  type = number
  default = 80
}

variable "cird_all" {
    description = "cird from all netrowrks"
    type        = list(string)
    default     = ["0.0.0.0/0"]
  
}