cell="fulladder"
file="sp_out.txt"
key1="tdrr"
keys=("tdrr" "tdfr" "\$DATA1" ".TITLE")
inSignal=()
outSignal=()
outCap=()
riseValues=()
fallValues=()

#cut -d " " << $file

echo ${keys[*]}

valueFlag=0

# extract propagation delay from file $1 (a .mt0 file)
# concatenate average of all measurements to file $2
extract_prop_delay () {
  local infile=$1
  local outfile=$2
  
  # variables to store data read from input file
  local valueFlag=0
  local inSignal=()
  local outSignal=()
  local outCap=()
  local riseValues=()
  local fallValues=()

  while IFS=" " read  -a k; do
    # get measured values (lines after tdfr and tdrr)
    [[ ${k[*]} =~ "tdrr" ]] && valueFlag=1 && continue
    [[ ${k[*]} =~ "tdfr" ]] && valueFlag=2 && continue
    
    # get sim parameters
    if [[ "SIMPARAM:" == ${k[0]} ]]; then
      #echo "${k[1]} > ${k[2]}"
      inSignal=(${inSignal[*]} ${k[1]})
      outSignal=(${outSignal[*]} ${k[2]})
      outCap=(${outCap[*]} ${k[3]})
    fi
  
    # handle rising input measurements
    if [[ $valueFlag == 1 ]]; then
      echo ${k[*]}
      riseValues=(${riseValues[*]} ${k[0]})
      fallValues=(${fallValues[*]} ${k[1]})
      valueFlag=0
    fi
  
    # handle falling input measurements
    if [[ $valueFlag == 2 ]]; then
      echo ${k[*]}
      riseValues=(${riseValues[*]} ${k[0]})
      fallValues=(${fallValues[*]} ${k[1]})
      valueFlag=0
    fi
  done <"$infile"

  echo "Rise values: ${riseValues[*]}"
  echo "Fall values: ${fallValues[*]}"
  echo "In signal: ${inSignal[*]}"
  echo "Out signal: ${outSignal[*]}"
  echo "Out Capacitance: ${outCap[*]}"

  # Lists and variables to average all measurements
  local currentIn=${inSignal[0]}
  local currentOut=${outSignal[0]}
  local currentCap=${outCap[0]}
  local nr=0
  local nf=0
  local riseTotal=0
  local fallTotal=0
   
  # Temporary values for floating point arithmetic
  local temp1=0
  local temp2=0
  local temp=0
  for ((i=0; i<${#riseValues[@]}; i++)); do
    if [[ $currentIn != ${inSignal[$i]} || $currentOut != ${outSignal[$i]} || $currentCap != ${outCap[$i]} ]]
    then
      # convert to picoseconds unit and take average
      temp1=$(echo "${riseTotal}/${nr}*10^12" | bc -l)
      # shorten the output to 2 decimal precision
      temp1=$(echo "scale=2; $temp1 * 100 / 100" | bc)
    
      #similarly for fall values
      temp2=$(echo "${fallTotal}/${nf}*10^12" | bc -l)
      temp2=$(echo "scale=2; $temp2 * 100 / 100" | bc)
    
      echo $currentIn $currentOut $currentCap rise:$temp1 fall:$temp2
      currentIn=${inSignal[$i]}
      currentOut=${outSignal[$i]}
      currentCap=${outCap[$i]}
      nr=0
      nf=0
      riseTotal=0
      fallTotal=0
    fi
  
    if [[ ${riseValues[$i]} != "failed" ]]; then
      nr=$((nr + 1))
      # convert riseValue[i] from scientific notation to a decimal number
      temp=$(echo "${riseValues[$i]}" | sed -r 's/[e]+/*10^/g' | bc -l)
      # add temp to total
      riseTotal=$(echo "${temp}+${riseTotal}" | bc -l)
      echo $temp
      echo $riseTotal
      echo $nr
    fi
  
    if [[ ${fallValues[$i]} != "failed" ]]; then
      nf=$((nf + 1))
      # convert riseValue[i] from scientific notation to a decimal number
      temp=$(echo "${fallValues[$i]}" | sed -r 's/[e]+/*10^/g' | bc -l)
      # add temp to total
      fallTotal=$(echo "${temp}+${fallTotal}" | bc -l)
    fi
  done

  # convert to picoseconds unit and take average
  temp1=$(echo "${riseTotal}/${nr}*10^12" | bc -l)
  temp1=$(echo "scale=2; $temp1 * 100 / 100" | bc)

  temp2=$(echo "${fallTotal}/${nf}*10^12" | bc -l)
  temp2=$(echo "scale=2; $temp2 * 100 / 100" | bc)
    
  echo $currentIn $currentOut $currentCap rise:$temp1 fall:$temp2
  currentIn=${inSignal[$i]}
  currentOut=${outSignal[$i]}
}

extract_prop_delay $file databook.txt
