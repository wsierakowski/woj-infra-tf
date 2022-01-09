variable "bucket_list" {
    default = {}
    description = "list of bucket names and properties"
}

variable "cost_center" {
    default = "dublin"
    description = "Cost center city name"
}

variable "sns_notifications_email" {
    description = "Email use to set up SNS subscription for db state change events"
}