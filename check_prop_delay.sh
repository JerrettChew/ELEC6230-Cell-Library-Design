declare -A truth_table
cell="fulladder"
globallist=( Vdd! GND! )
inlist=( A B Cin )
outlist=( S Cout )
output_cap=( 2fF 32fF )

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

print_truth_table () {
  for ((i=0;i<$1;i++)); do
    out=""
    for ((j=0;j<$2;j++)); do
        out+="${truth_table[$i,$j]} "
    done
  echo $out
  done
}

check_prop_delay () {
  echo "cell: $cell"
  echo "global: ${globallist[*]}"
  echo "in: ${inlist[*]}"
  echo "out: ${outlist[*]}"
  echo "output capacitance: ${out_cap[*]}"

  # generate spice
  ext2sp -f $cell > /dev/null

  # clear output file
  echo > sp_out.txt

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

  cp $cell.sp ${cell}_temp.sp

  generate_truth_table $(( ${#inlist[@]} - 1 ))

  pow=$((2 ** ( ${#inlist[@]} - 1 ) ))
  print_truth_table $pow $(( ${#inlist[@]} - 1 ))

  for(( i=0; i<${#inlist[@]}; i++)); do
    for(( j=0; j<${#outlist[@]}; j++)); do
      for (( h=0; h<${#output_cap[@]}; h++ )); do
        echo "Finding propagation delay for ${inlist[i]} > ${outlist[j]}, capacitance ${output_cap[h]}"
        for (( m=0; m<$pow; m++)); do
          for(( k=0; k<2; k++)); do
            cp ${cell}_temp.sp $cell.sp
    
            # insert circuit to be simulated
            n=$(find_line_num_in_file "Vsupply" $cell.sp 0)
            sed -i "$((n + 2))i **Propagation Delay Simulation\n" $cell.sp
            sed -i "$((n + 3))i $scale" $cell.sp
            sed -i "$((n + 4))i X${cell}_driver ${outlist[*]} ${inlist[*]} Vdd GND $cell" $cell.sp
            sed -i "$((n + 5))i Ctest GND ${outlist[$j]} ${output_cap[h]}" $cell.sp
    
            # insert input signals
            line="Specify input signals here"
            n=$(find_line_num_in_file $\line $cell.sp 0)
            echo "Inputs: "
      
            index=0
            for(( l=0; l<${#inlist[@]}; l++)); do
              if [[ $l == $i ]]; then
	        # input signal to be tested
                # run two simulations, one with rising edge, one with falling edge
                input="V$l ${inlist[$l]}"
	        if [[ $k -eq 0 ]]; then
                  input="V$i ${inlist[$i]} GND PWL(0NS 0V  5NS 0V  5.25NS ${Vsupply}V)"
	          echo "${inlist[$i]} 0->1"
                else
                  input="V$i ${inlist[$i]} GND PWL(0NS ${Vsupply}V  5NS ${Vsupply}V  5.25NS 0V)"
	          echo "${inlist[$i]} 1->0"
                fi
              else
	        # other signals
                # generate inputs based on truth table (covers all possiblities)
                [[ ${truth_table[$m,$index]} == 1 ]] && Vin=${Vsupply} || Vin=0
                input="V$l ${inlist[$l]} GND PWL(0NS ${Vin}V)"
                echo "${inlist[$l]} ${truth_table[$m,$index]}"
                #echo $index
	  
                index=$(( $index + 1 ))
              fi
      
              sed -i "$((n+l+4))i $input" $cell.sp
              #echo ${truth_table[$m,$l]} $input
            done
    
            # insert simulation measurements
            line="Save results for display"
            n=$(find_line_num_in_file $\line $cell.sp 0)
            n=$((n - 1))

            if [[ $k == 0 ]]; then
              measure1=".measure TRAN tdrr   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=0NS RISE=1"
              measure2=".measure TRAN tdrf   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=0NS FALL=1"
        else
              measure1=".measure TRAN tdfr   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=4NS FALL=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=4NS RISE=1"
              measure2=".measure TRAN tdff   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=4NS FALL=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=4NS FALL=1"
            fi
            sed -i "${n}i $measure1" $cell.sp
            sed -i "$((n+2))i $measure2" $cell.sp
    
            #cat $cell.sp
    
            # run simulation
            hspice $cell.sp $cell.spice >> /dev/null
            echo "Running simulation..."
            echo "----------------------------------------------------"
	    # cat $cell.mt0
	    echo "SIMPARAM: ${inlist[i]} ${outlist[j]} ${output_cap[h]}" >> sp_out.txt
            cat $cell.mt0 >> sp_out.txt
          done
          unit3=$(( $i * ${#outlist[@]} * ${#output_cap[@]} ))
          unit2=$(( $j * ${#output_cap[@]} ))
          unit1=$h
          percentage=$(( ($unit1 + $unit2 + $unit3) * 100 / (${#inlist[@]} * ${#outlist[@]} * ${#output_cap[@]}) ))
          echo "Current percentage: $unit3 * $unit2 * $unit1 = $percentage"
        done
      done
    done
  done
}

check_prop_delay

