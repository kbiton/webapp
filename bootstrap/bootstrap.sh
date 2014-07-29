#!/bin/bash
#Chef-Solo BootStrap Script , this is the script that will be executed on first run it will:
# - Install chef-solo to the lastest version using opscode bash script
# - Create a cron job that will execute chef-solo every 20 min
#####TO DO######
# - Check if wget/curl return 0 bytes file and report that!
#
#Version 0.1 - Initial
#Version 0.2 - Added AWS Python CLI installation so I can make secure calls to S3
#Version 0.3 - Replaced wget/curl with aws s3 cli tool
#Version 0.4 - Due due apt failures added apt-get -y update
#Version 0.5 - Adjusted the script by adding 2 arguments
##############################################################
BUCKET="$2"
REGION="$1"
SOLOBOOT="chef/boot/install.sh"
SOLOROLES="chef/roles/roles.tar.gz"
SOLOCOOKBOOKS="chef/cookbooks/solo-all.tar.gz"
SOLORB="chef/config/solo.rb"
NODEJSON="chef/config/node.json"
SOLOSCRIPT="install.sh"
LOCAL="/usr/local/bootstrap"
LOG="/var/log/bootstrap.log"
SOLOLOG="/var/log/chef-solo-install.sh.log"
##############################################################
##############################################################
usage()
 {
 cat << EOF

 usage: $0 AWS-REGION BUCKET-NAME 

 EOF
 }
 
 if [[ -z $REGION ]] || [[ -z $BUCKET ]]
  then
       usage
       exit 1
   fi
   
exists() {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

#Functions
error_n_exit()
{

echo "`date`:ERROR $1 Exiting..." >> $LOG
/bin/cat /tmp/stderr >> $LOG

}
ok_n_cont()
{
echo "`date`:OK $1" >> $LOG
}
mkdir -p $LOCAL || error_n_exit "Could not create folders"
create_folders()
{
mkdir -p  /var/chef-solo/cache /var/chef-solo/cache/cookbooks /etc/chef /var/chef-solo/roles /var/chef-solo/check-sum
if [ "$?" == "0" ];then
  return 0
else
  return 1
fi
}


#Create Folders
create_folders
 if [ "$?" != "0" ];then
   error_n_exit "Failed to create folders"
 else
   ok_n_cont "Created Folders"
 fi
#Get Chef-Solo Install Script , Chef-Solo generated configuration files
##
###Copy the chef-solo install.sh master script
aws s3 --region $REGION cp s3://$BUCKET/$SOLOBOOT "$LOCAL/$SOLOSCRIPT" 2>>/tmp/s3out
aws s3 --region $REGION cp s3://$BUCKET/$SOLORB "/etc/chef/solo.rb" 2>>/tmp/s3out
aws s3 --region $REGION cp s3://$BUCKET/$NODEJSON "/etc/chef/" 2>>/tmp/s3out
aws s3 --region $REGION cp s3://$BUCKET/$SOLOROLES "/var/chef-solo/roles/roles.tar.gz" 2>>/tmp/s3out
  cd /var/chef-solo/roles/ || error_n_exit "could not change dir to roles"
  tar xfz roles.tar.gz || error_n_exit "could not extract roles.tar.gz"
aws s3 --region $REGION cp s3://$BUCKET/$SOLOCOOKBOOKS "/var/chef-solo/cache/cookbooks" 2>>/tmp/s3out
  cd /var/chef-solo/cache/cookbooks && tar xfz solo-all.tar.gz || error_n_exit "could not extract solo-all.tar.gz"
#Lets call OpsCode Chef-solo master install script , this will install chef-solo (omnibus)

    chmod +x $LOCAL/$SOLOSCRIPT || error_n_exit "Could not set +x to to $LOCAL/$SOLOSCRIPT"
    source $LOCAL/$SOLOSCRIPT 2>&1 >> $SOLOLOG
     if [ "$?" == "0" ];then
      ok_n_cont "Looks like Chef-Solo Was Installed Successfully Check $SOLOLOG for more info"
     else
      error_n_exit "Chef-solo failed to install, check $SOLOLOG for more info"
     fi
#Creating cron
mkdir -p /usr/local/scripts
### Lets set the cron job that will execute chef-solo every 20 minutes
aws s3 --region $REGION cp s3://$BUCKET/others/solocron.sh "/usr/local/scripts/solocron.sh"
chmod +x "/usr/local/scripts/solocron.sh"
##Setup the cronjob
echo "*/20 * * * *   /usr/local/scripts/solocron.sh" >> /tmp/solocrontab
#Enable the cron
crontab /tmp/solocrontab
rm -f /tmp/solocrontab
### lets end by setting permissions
chown root.root "/etc/chef" -R
chown root.root "/usr/local/scripts" -R
chown root.root "/var/chef-solo" -R
#Lets execute apt-get -y update
apt-get -y update
## Execute first chef-solo run ....
/usr/bin/chef-solo -L /var/log/solorun.log
#end
#
exit 0
