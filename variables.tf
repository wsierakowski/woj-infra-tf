# Conventions:
#  - Use the plural form in a variable name when type is list(...) or map(...)
#  - Order keys in a variable block like this: description , type, default, validation.
#  - Always include description on all variable
# More: https://www.terraform-best-practices.com/naming#variables

variable "bucket_list" {
    default = {}
    description = "list of bucket names and properties"
}

variable "cost_center" {
    default = "dublin"
    description = "Cost center city name"
}