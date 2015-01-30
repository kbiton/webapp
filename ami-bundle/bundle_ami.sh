#!/bin/bash

usage()
{
cat << EOF
usage: $0 options
	
This script takes CFN parameters, Deploy a CFN Stack and if successful, produces an AMI

Requirements:

- The Instance that is going to bootstrap the stack will need IAM Permissions to execute the CFN Stack
- The below Parameters are all REQUIRED, they will used as Input Params for the CFN stack 
- The Instance that will bootstrap the stack 

Use Cases

- Build a continues integration pipeline , starting from Jenkins: Build Artifcats,call this script with params,Produce AMI
- Use it as an AMI producer , plug it into any process you already use
	
OPTIONS:
	-h	Show this message
	-n	Name of CloudFormation stack
	-a	Name to use for generated AMI
	-v	The VPC ID
	-s  The Subnet ID
	-k  EC2 Keypair Name
	-i  EC2 instance type to use
EOF
}

# Parse options
while getopts "h:n:s:a:v:k:e:i:" OPTION
do
	case $OPTION in
		h)
			usage
			exit 1
			;;
		n)
			STACK_NAME=$OPTARG
			;;
		a)
			AMI_NAME=$OPTARG
			;;
		v)
			VPC_ID=$OPTARG
			;;
		s)
			SUBNET_ID=$OPTARG
			;;
		k)      
			KEY_PAIR=$OPTARG
			;;
		i)
			INSTANCE_SIZE=$OPTARG	
			;;	
		?)
			usage
			exit
			;;
	esac
done 

# Validation
if [[ -z "${STACK_NAME}" ]] || [[ -z "${AMI_NAME}" ]] || [[ -z "${VPC_ID}" ]] || [[ -z "${SUBNET_ID}" ]] || [[ -z "${KEY_PAIR}" ]] || \
   [[ -z "${INSTANCE_SIZE}" ]] 
  then
	usage
	exit 1
fi

function log_exit_error {
	
	logger -s -p local3.error -t CFNDEPLOY:ERROR $1
	
}

function log_and_cont {
	
	logger -s -p local3.info -t CFNDEPLOY:INFO $1
	
}

function exists {
	
command -v $1
	if [ "$?" != "0" ];then
	  log_exit_error "command $1 could not be found... bailing out" 
    fi

}

# Lets randomize the stack name to avoid duplication
STACK_NAME = $STACK_NAME-$(date +%s)

# launching the stack
log_and_cont "Launching CFN stack $STACK_NAME"

# Launch selected stack and capture its name
aws cloudformation create-stack --stack-name $STACK_NAME --template-url \
"https://s3-eu-west-1.amazonaws.com/kbitpub/cfn-jenkins-demo/webapp-cfn.json" \
--disable-rollback --timeout-in-minutes 30 --capabilities CAPABILITY_IAM \
--parameters ParameterKey=keypair,ParameterValue=$KEY_PAIR 

# 
sleep 1

# Continue checking status until it is no longer CREATE_IN_PROGRESS
while [ true ]; do
	# Get stack status
	# TODO change this to use --stack-status
	# stack_status=$(cfn-list-stacks --stack-status CREATE_COMPLETE | grep $STACK_NAME | awk 'BEGIN{FS="[ ]+"}{print $5}')
  stack_status=$(cfn-describe-stacks $STACK_NAME | grep $STACK_NAME" " | awk 'BEGIN{FS="[ ][ ]+"}{print $3}')

  # If status is not CREATE_IN_PROGRESS, exit the loop
  if [ $stack_status != "CREATE_IN_PROGRESS" ]
	then
		break
	else
		echo "Status is" $stack_status". Checking progress..."  >> bundle_ami.log
		sleep 40
	fi
done

# wait before moving on to the next, cfn-describe, call
sleep 5
# Handle the resulting stack status
if [ $stack_status == "CREATE_COMPLETE" ]
then
		echo "Stack created successfully. Now bundling AMI from instance."  >> bundle_ami.log
		
		# Well, before we bundle the AMI, we need to find the instance ID. Let's describe
		# the stacks and find that tidbit
		instance_id=$(cfn-describe-stacks $STACK_NAME | grep $STACK_NAME" " | awk 'BEGIN{FS="[ ][ ]+"}{print $5}' | grep -o "i-.*$")
		
		# Make sure we got an instance ID from the output
		if [ -z "${instance_id-x}" ] ; then
			echo "Could not parse instance ID from output of cfn-describe-stacks."
			exit -1
		fi
		
		# Now we'll run the python script to bundle the new instance as an AMI.
		echo "Bundling instance" $instance_id". This may take a few minutes." >> bundle_ami.log
		
		ami_id=$(./bundle_ami.py -a $AWS_ACCESS_KEY_ID -k $AWS_SECRET_ACCESS_KEY -i $instance_id -n $AMI_NAME -d $AMI_NAME)
		
		# TODO: Error-check the output of the python script rather than assuming it succeeded!
		echo $ami_id | tee -a bundle_ami.log
		exit 1
else
		echo "Stack did not create successfully. CloudFormation reported status" $stack_status
fi
