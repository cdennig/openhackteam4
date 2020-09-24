#!/bin/bash
WEBAPP=$1
RESOURCEGROUP=$2
MINUTES=$3
RAMPUPPERCENTAGE=$4
ENDPOINT=$5
regularExpression='^[0-9]+$'

declare -i duration=5
declare hasUrl=""
declare -i status200count=0

healthcheck() {
    declare url=$ENDPOINT
    echo $url
    result=$(curl -i $url 2>/dev/null | grep HTTP/2)
    echo $result
}

if ! ([[ $MINUTES =~ $regularExpression ]] && [[ $RAMPUPPERCENTAGE =~ $regularExpression ]]);
then
   echo "error: Not a number" >&2;
else
 secsToRumpUp=$(awk "BEGIN {print ($RAMPUPPERCENTAGE/100)*($MINUTES*60)}")
 rumpup=$RAMPUPPERCENTAGE;
 incremental=$(awk "BEGIN {print ($MINUTES*60)/$secsToRumpUp}")
 echo "Your webapp $WEBAPP in the resource group $RESOURCEGROUP will be traffic-routed in the next $MINUTES minutes every $secsToRumpUp secs a $RAMPUPPERCENTAGE %";
 for (( c=0; c<$incremental; c++ ))
 do      
   echo "Incrementing staging slot to $rumpup %";   
   az webapp traffic-routing set --distribution staging=$rumpup --name $WEBAPP --resource-group $RESOURCEGROUP
   
   for i in {1..12}
   do
     result=$(curl -i $ENDPOINT 2>/dev/null | grep HTTP/2)
     declare status
     if [[ -z $result ]]; then 
        status="N/A"
        echo "Site not found"
     else
       status=${result:7:3}
       timestamp=$(date "+%Y%m%d-%H%M%S")
       if [[ -z $hasUrl ]]; then
         echo "$timestamp | $status "
       else
         echo "$timestamp | $status | $ENDPOINT " 
       fi 
        
       if [ $status -eq 200 ]; then
         ((status200count=status200count + 1))

          if [ $status200count -gt 5 ]; then
              break
          fi
       fi

       sleep $duration
     fi
   done
#    sleep "$secsToRumpUp"
   if [ $status200count -gt 5 ]; then
     echo "API UP"
     # APISTATUS is a pipeline variable
     APISTATUS="Up"
     let "rumpup += RAMPUPPERCENTAGE";
     status200count=0
   else
    echo "API DOWN"
    APISTATUS="Down"
    az webapp traffic-routing clear --name $WEBAPP --resource-group $RESOURCEGROUP
    exit 1;
   fi
  done
  echo "Rolling back traffic-routing..."
  az webapp traffic-routing clear --name $WEBAPP --resource-group $RESOURCEGROUP
  echo "Swapping $WEBAPP"
  az webapp deployment slot swap  -g $RESOURCEGROUP -n $WEBAPP --slot staging --target-slot production
fi