#Purpose

The scripts in this folder are intended to automate the addition and removal of Azure Public IPs to Azure route tables. This enables traffic from Azure VMs to Azure public services like Azure Backup to take the most direct path which is especially useful in forced tunneling scenarios or in cases where you don't want this type of traffic to flow through firewalls in an Azure VNet.

##Usage

Create an Azure Automation account being sure to enable Azure Run As Connection and add the scripts as runbooks. Additionally, you'll need to submit a support request to increase the quota of user defined routes in your route table from 100 to the max of 400. When you submit your request, include the following information:

* Subscription Id
* Name of the resource group which contains your route table
* Name of the route table

##Scheduling

The Azure Public IP list document is updated every Wednesday and the changes go into effect the following Monday. Because of this, the recommended schedule is to run the add script every Sunday and the remove script every Tuesday.

When scheduling the add script, you'll need to include values for the following parameters:

* Azure region of the route table
* Name of the resource group which contains your route table
* Name of the route table
* Max number of routes (this is included in the case you haven't yet submitted the support request and would like to try the script out. For production scenarios, you should set this to 400)

When scheduling the remove script, you'll need to include values for the following parameters:

* Azure region of the route table
* Name of the resource group which contains your route table
* Name of the route table
* Comma separated list of routes to ignore.