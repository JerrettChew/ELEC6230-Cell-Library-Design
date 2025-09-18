declare -A truth_table
cell="fulladder"
globallist=( Vdd! GND! )
inlist=( A B Cin )
outlist=( S Cout )
output_cap=( 1fF 2fF 8fF 32fF )
C_min="15fF"
C_max="30fF"

# inputs $1 input line
#        $2 input file
#        $3 starting from line number
find_line_num_in_file () {
  eval in_line="$1"
  eval in_file="$2"
  eval line_num="$3"
  
  #debug inputs
  #echo $in_line >&2
  #echo $in_file >&2
  #echo $line_num >&2
  #echo "---" >&2
  
  # get tail of file starting from line number $1 |
  # line number of find "in_line" in the file
  local line=$(tail -n +$(("$line_num" + 1)) "$in_file" | grep -n "$in_line" | cut -d : -f 1)
  echo $line
}

generate_truth_table () {
  pow=$((2 ** $1))
  
  for ((j=0;j<$pow;j++)); do
    
    #convert number to binary array 
    for ((k=0;k<$1;k++)); do
      bin=$(( ( $j & ( 1 << $k ) ) >> $k ))
      
      #store in matrix
      truth_table[$j,$(($1-$k-1))]=${bin}
    done
  done
}

print_mat () {
  for ((i=0;i<$1;i++)); do
    out=""
    for ((j=0;j<$2;j++)); do
        out+="${truth_table[$i,$j]} "
    done
  echo $out
  done
}

check_input_capacitance () {
  local outfile=$1

  echo "cell: $cell"
  echo "global: ${globallist[*]}"
  echo "in: ${inlist[*]}"
  echo "out: ${outlist[*]}"
  echo "output capacitance: $COut"

  # generate spice
  ext2sp -f $cell > /dev/null

  # get scaling option from file
  n=$(find_line_num_in_file "scale=" $cell.spice 0)
  scale=$(sed -n "${n}p" $cell.spice)

  # convert .spice into a subcircuit
  sed -i "2i .SUBCKT $cell ${outlist[*]} ${inlist[*]} Vdd GND" $cell.spice
  n=$(wc -l $cell.spice | cut -d " " -f 1)
  sed -i "${n}i .ENDS $cell" $cell.spice

  # find supply voltage to be used
  n=$(find_line_num_in_file "Vsupply" $cell.sp 0)
  Vsupply=$(sed -n "${n}p" $cell.sp | cut -d " " -f 4)
  Vsupply=${Vsupply::-1}

  # change simulation command
  n=$(find_line_num_in_file ".TRAN" $cell.sp 0)
  sed -i "${n}s/.*/.model OPT1 opt/" $cell.sp
  sed -i "$((n + 1))i .TRAN 1PS 10NS SWEEP OPTIMIZE=optc RESULTS=tdavgc MODEL=OPT1" $cell.sp

  cp $cell.sp ${cell}_temp.sp

  generate_truth_table $(( ${#inlist[@]} - 1 ))

  pow=$((2 ** ( ${#inlist[@]} - 1 ) ))
  print_mat $pow $(( ${#inlist[@]} - 1 ))

  for(( i=0; i<${#inlist[@]}; i++ )); do
    for (( m=0; m<$pow; m++ )); do
      echo "Finding input capacitance for ${inlist[i]}"
    
      cp ${cell}_temp.sp $cell.sp
    
      # insert circuit to be simulated
      n=$(find_line_num_in_file "Vsupply" $cell.sp 0)
      sed -i "$((n + 2))i **Input Capacitance Simulation\n" $cell.sp
      sed -i "$((n + 3))i $scale" $cell.sp
      sed -i "$((n + 4))i .param CLOAD=OPTC(15fF, 1fF, 30fF)" $cell.sp
      driver0="X${cell}_driver0"
      load0="X${cell}_load0"
      driver1="X${cell}_driver1"
    
      for (( j=0; j<${#outlist[@]}; j++)); do
        driver0="${driver0} ${outlist[j]}00"
        load0="${load0} ${outlist[j]}01"
        driver1="${driver1} ${outlist[j]}10"
      done
      
      driver0="${driver0} ${inlist[*]}"
      driver1="${driver1} ${inlist[*]}"
      for (( j=0; j<${#inlist[@]}; j++)); do
        if [[ $j -eq $i ]]; then
          load0="${load0} ${outlist[0]}00"
        else
          load0="${load0} ${inlist[j]}"
        fi
      done
      sed -i "$((n + 5))i $driver0 Vdd GND $cell" $cell.sp
      sed -i "$((n + 6))i $load0 Vdd GND $cell" $cell.sp
      sed -i "$((n + 7))i $driver1 Vdd GND $cell" $cell.sp
      sed -i "$((n + 8))i Cload GND ${outlist[0]}10 CLOAD" $cell.sp
    
      # insert input signals
      line="Specify input signals here"
      n=$(find_line_num_in_file $\line $cell.sp 0)
      echo "Inputs: "
      
      index=0
      for(( l=0; l<${#inlist[@]}; l++)); do
        if [[ $l == $i ]]; then
          input="V$l ${inlist[$l]}"
	else
          # generate inputs based on truth table
          [[ ${truth_table[$m,$index]} == 1 ]] && Vin=${Vsupply} || Vin=0
          input="V$l ${inlist[$l]} GND PWL(0NS ${Vin}V)"
          echo "${inlist[$l]} ${truth_table[$m,$index]}"
	  echo $index
	  
          index=$(( $index + 1 ))
	fi
      
        sed -i "$((n+l+4))i $input" $cell.sp
        #echo ${truth_table[$m,$l]} $input
      done
      
      # change the input being tested against to rising or falling edge
      line="V$i"
      n=$(find_line_num_in_file $line $cell.sp 0)
      # run two simulations, one with rising edge, one with falling edge
      input="V$i ${inlist[$i]} GND PWL(0NS 0V  2.5NS 0V  2.75NS ${Vsupply}V 7.5NS ${Vsupply}V  7.75NS 0V)"
      sed -i "${n}s/.*/$input/" $cell.sp
      
      # insert simulation measurements
      line="Save results for display"
      n=$(find_line_num_in_file $\line $cell.sp 0)
      n=$((n - 1))

      #if [[ $k == 0 ]]; then
        measure1=".measure TRAN tdr   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[0]}00) VAL='0.5*$Vsupply' TD=0NS"
        measure2=".measure TRAN tdf   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=5NS FALL=1 \n+TARG v(${outlist[0]}00) VAL='0.5*$Vsupply' TD=5NS"
      #else
        measure3=".measure TRAN tdrc   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[0]}10) VAL='0.5*$Vsupply' TD=0NS"
        measure4=".measure TRAN tdfc   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=5NS FALL=1 \n+TARG v(${outlist[0]}10) VAL='0.5*$Vsupply' TD=5NS"
      #fi
      measure5=".measure TRAN tdavg PARAM='(tdr+tdf)/2'"
      measure6=".measure TRAN tdavgc PARAM='(tdrc+tdfc)/2' GOAL=tdavg"
      sed -i "${n}i $measure1" $cell.sp
      sed -i "$((n+2))i $measure2" $cell.sp
      sed -i "$((n+4))i $measure3" $cell.sp
      sed -i "$((n+6))i $measure4" $cell.sp
      sed -i "$((n+8))i $measure5" $cell.sp
      sed -i "$((n+9))i $measure6" $cell.sp
      
      #cat $cell.sp
      
      # run simulation
      hspice $cell.sp $cell.spice >> /dev/null
      echo "Running simulation | in: ${inlist[i]} "
      #cat $cell.mt0
      echo "SIMPARAM: ${inlist[i]}" >> $outfile
      cat $cell.mt0 >> $outfile
    done
  done
}

# clear output file
echo > sp_out.txt
  
check_input_capacitance sp_out.txt
