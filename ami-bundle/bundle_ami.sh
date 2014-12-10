#!/bin/bash

usage()
{
cat << EOF
usage: $0 options
	
This script takes CFN paramters and at the end of the day suppose to produce an AMI with your install software

Requirements:

- The Instance that is going to bootstrap the stack will need IAM Permissions to execute the CFN Stack
- The below Parameters are all REQUIRED, they will used as Input Params for the CFN stack 
- The Instance that will bootstrap the stack 

Use Cases

- Use as a post build step for Jenkins , create the stack , deploy software , delete stack
- Use it as an AMI producer , plug it into any process you already use
	
OPTIONS:
	-h	Show this message
	-s	Name of CloudFormation stack
	-a	Name to use for generated AMI
	-d	Description to use for generated AMI
	-k  EC2 Keypair Name
	-i  EC2 instance type to use
EOF
}

# Parse options
while getopts "h:s:a:d:k:e:i:" OPTION
do
	case $OPTION in
		h)
			usage
			exit 1
			;;
		s)
			STACK_NAME=$OPTARG
			;;
		a)
			AMI_NAME=$OPTARG
			;;
		d)
			AMI_DESC=$OPTARG
			;;
		k)      
			KEY_PAIR=$OPTARG
			;;
		i)
			INSTANCE_TYPE=$OPTARG	
			;;	
		?)
			usage
			exit
			;;
	esac
done

echo $KEY_PAIR  >> bundle_ami.log
echo $RECIPE_LOC  >> bundle_ami.log
echo $INSTANCE_TYPE  >> bundle_ami.log

# Validate required parameters
if [[ -z "${STACK_NAME}" ]] ||  [[ -z "${AMI_NAME}" ]] ||  [[ -z "${AMI_DESC}" ]] ; then
	usage
	exit 1
fi

# Make sure the necessary AWS credentials are present for boto. 
if [[ -z "${AWS_ACCESS_KEY_ID}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY}" ]] ; then
	echo "Error: Both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set in your environment to use this tool."
	exit -1
fi

# If an AMI description isn't provided, set it to the AMI Name
if [[ -z "${AMI_DESC}" ]] ; then
	AMI_DESC=$AMI_NAME
fi

# Make sure STACK_TYPE is correct
if [[ $STACK_TYPE != "amm-web" ]] && [[ $STACK_TYPE != "amm-transcoder" ]] && [[ $STACK_TYPE != "amm-load" ]] ; then
	echo "Invalid stack name."
	usage
	exit 1
fi

# Let the user know we're launching the stack
echo "Launching stack" $STACK_NAME  >> bundle_ami.log

# Launch selected stack and capture its name
createstack=$(cfn-create-stack $STACK_NAME --disable-rollback --template-url ${RECIPE_LOC}/amm/cfn/amm-ami.template --capabilities CAPABILITY_IAM --parameters="S3Bucket=${RECIPE_LOC};KeyName=${KEY_PAIR};InstanceType=${INSTANCE_TYPE};ChefSoloTemplateURL=${RECIPE_LOC}/amm/cfn/amm-ami-chef.template;ChefRecipesURL=${RECIPE_LOC}/amm/amm-chef-solo.tar.gz;ChefRecipe=${STACK_TYPE}")
echo "Stack $STACK_NAME launched. Status will be polled until creation is complete..."  >> bundle_ami.log
# wait before moving on to the next, cnf-list-stacks, call
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
