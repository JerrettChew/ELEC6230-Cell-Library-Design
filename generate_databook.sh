#!/bin/bash

SIM_ALL=0
cell_lib=("scandtype" "scanreg" "fulladder" "halfadder" "mux2" "nand2" "xor2" "nand3" "nand4" "inv" "buffer" "trisbuf")

comb=("inv" "buffer" "nand" "nor" "and" "or" "xor" "xnor" "fulladder" "halfadder" "mux2" "smux2" "smux3" "trisbuf")
declare -A gray_bin_mat
declare -A truth_table
declare -A sv_output
globallist=()
inlist=()
outlist=()
clockSignal=""
synchronous_flag=0
output_cap=( 4fF 8fF 32fF 64fF )
databook_file="databook.txt"
cellsSkipped=()

strindex() {
    x="${1%%"$2"*}"
    [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
}

inverse_gray () {
  local n=0;
  local g=$1;
  for ((; g; g = g >> 1)); do
    n=$(( $n ^ $g ))
  done
  
  echo $n
}

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
  
  # get tail of file starting from line number $1 |
  # line number of find "in_line" in the file
  local line=$(tail -n +$(("$line_num" + 1)) "$in_file" | grep -n "$in_line" | cut -d : -f 1)
  echo $line
}

# $1 is the .mag file of the cell while $2 is the .ext file
# $3 and $4 are boundary units in magic, $3 is x, $4 is y
check_in_out () {
  local mag_file=$1
  local ext_file=$2
  local boundary1=$3
  local boundary2=$4

  # test1 finds "<< labels >>" in a magic file, test2 finds next instance of "<<"
  local line1="<< labels >>"
  local line2="<< "
  local n1=$(find_line_num_in_file "\${line1}" $mag_file 0)
  local n2=$(find_line_num_in_file "\${line2}" $mag_file $n1)
  
  # label list from .mag, stores boundary ports
  local labels
  
  # loop through every line that specified labels
  for ((i = $n1 + 1 ; i < $n2 + $n1; i++)); do
    # tokenize every line using spaces as delimiter
    tokens=( $(sed -n "${i}p" $mag_file) )
    
    # add unique tokens to an array, the 7th element always contains the label
    # also check if label is a boundary label (boundary1, boundary2, and 0)
    if [[ ! " ${labels[*]} " =~ " ${tokens[7]} " && \
          " ${tokens[*]} " =~ " $boundary1 " || \
          " ${tokens[*]} " =~ " $boundary2 " || \
	  " ${tokens[*]} " =~ " 0 " ]]; then
      labels+=(${tokens[7]})
    fi
  done
  
  # find global signal as specified by an ending '!'
  for i in "${labels[@]}"; do
    if [[ $i = *! && \
          (! " ${globallist[*]} " =~ " $i ")]]; then
      globallist+=($i);
    fi
  done
		
  # check source and drain connections
  TEST=$(grep -n "fet" $ext_file | cut -d "\"" -f 6)
  TEST+=" "$(grep -n "fet" $ext_file | cut -d "\"" -f 8)
  tokens=( $TEST )
    
  # check for unique nodes that are labels (ports) and are not global signals
  for i in "${tokens[@]}"; do
    if [[ (! " ${outlist[*]} " =~ " $i ") && \
          (" ${labels[*]} " =~ " $i ") && \
          (! " ${globallist[*]} " =~ " $i ")]]; then
      outlist+=($i)
    fi
  done
			
  # check gate connections
  TEST=$(grep -n "fet" $ext_file | cut -d "\"" -f 4)
  tokens=( $TEST )
  for i in "${tokens[@]}"; do
    if [[ (! " ${inlist[*]} " =~ " $i ") && \
          (" ${labels[*]} " =~ " $i ") && \
          (! " ${outlist[*]} " =~ " $i ")]]; then
      inlist+=($i)
    fi
  done
  
  # loop through every line that specified labels
  for ((i = $n1 + 1 ; i < $n2 + $n1; i++)); do
    tokens=( $(sed -n "${i}p" $1) )
    
    # add port positions of input port 
    if [[ " ${inlist[*]} " =~ " ${tokens[7]} " ]]; then
      inportlist+=(${tokens[7]})
      inportlist+=(${tokens[2]})
      inportlist+=(${tokens[3]})
      inportlist+=(${tokens[4]})
      inportlist+=(${tokens[5]})
    fi
    
    # add port positions of output port 
    if [[ " ${outlist[*]} " =~ " ${tokens[7]} " ]]; then
      outportlist+=(${tokens[7]})
      outportlist+=(${tokens[2]})
      outportlist+=(${tokens[3]})
      outportlist+=(${tokens[4]})
      outportlist+=(${tokens[5]})
    fi
    
    # add port positions of global port 
    if [[ " ${globallist[*]} " =~ " ${tokens[7]} " ]]; then
      globalportlist+=(${tokens[7]})
      globalportlist+=(${tokens[2]})
      globalportlist+=(${tokens[3]})
      globalportlist+=(${tokens[4]})
      globalportlist+=(${tokens[5]})
    fi
  done
}

# print port positions of a cell to given output file $1
print_port_pos () {
  local out_file=$1

  # input port
  local input_txt=""
  for ((j=${#inlist[@]} - 1; j>=0; j--)); do
    input_txt="${input_txt}${inlist[$j]}"
    for ((i=0; i<${#inportlist[@]}; i+=5)); do
      if [[ ${inportlist[$i]} == ${inlist[$j]} ]]; then
        # scale from lambda to microns
	pos1=$(echo "${inportlist[$i+1]}*$scale" | bc -l)
	pos2=$(echo "${inportlist[$i+2]}*$scale" | bc -l)
	pos3=$(echo "${inportlist[$i+3]}*$scale" | bc -l)
	pos4=$(echo "${inportlist[$i+4]}*$scale" | bc -l)
	# get 2 significant decimal places
	pos1=$(echo "scale=2; ${pos1}*100/100" | bc)
	pos2=$(echo "scale=2; ${pos2}*100/100" | bc)
	pos3=$(echo "scale=2; ${pos3}*100/100" | bc)
	pos4=$(echo "scale=2; ${pos4}*100/100" | bc)
	# append 0 to the front if number is 0.66 but written as .66
	if [[ $pos1 == .* ]]; then pos1="0$pos1"; fi
	if [[ $pos2 == .* ]]; then pos2="0$pos2"; fi
	if [[ $pos3 == .* ]]; then pos3="0$pos3"; fi
	if [[ $pos4 == .* ]]; then pos4="0$pos4"; fi
	
	input_txt="$input_txt | $pos1 $pos2 $pos3 $pos4"
      fi
    done
    NEWLINE=$'\n'
    input_txt="$input_txt${NEWLINE}"
  done
  echo "Input ports and positions (microns)" >> $out_file
  echo "$input_txt" >> $out_file
  
  # output port
  local output_txt=""
  for ((j=${#outlist[@]} - 1; j>=0; j--)); do
    output_txt="${output_txt}${outlist[$j]}"
    for ((i=0; i<${#outportlist[@]}; i+=5)); do
      if [[ ${outportlist[$i]} == ${outlist[$j]} ]]; then
        # scale from lambda to microns
	pos1=$(echo "${outportlist[$i+1]}*$scale" | bc -l)
	pos2=$(echo "${outportlist[$i+2]}*$scale" | bc -l)
	pos3=$(echo "${outportlist[$i+3]}*$scale" | bc -l)
	pos4=$(echo "${outportlist[$i+4]}*$scale" | bc -l)
	# get 2 significant decimal places
	pos1=$(echo "scale=2; ${pos1}*100/100" | bc)
	pos2=$(echo "scale=2; ${pos2}*100/100" | bc)
	pos3=$(echo "scale=2; ${pos3}*100/100" | bc)
	pos4=$(echo "scale=2; ${pos4}*100/100" | bc)
	# append 0 to the front if number is 0.66 but written as .66
	if [[ $pos1 == .* ]]; then pos1="0$pos1"; fi
	if [[ $pos2 == .* ]]; then pos2="0$pos2"; fi
	if [[ $pos3 == .* ]]; then pos3="0$pos3"; fi
	if [[ $pos4 == .* ]]; then pos4="0$pos4"; fi
	
	output_txt="$output_txt | $pos1 $pos2 $pos3 $pos4"
      fi
    done
    NEWLINE=$'\n'
    output_txt="$output_txt${NEWLINE}"
  done
  echo "Output ports and positions (microns)" >> $out_file
  echo "$output_txt" >> $out_file
  
  # global port
  local global_txt=""
  for ((j=${#globallist[@]} - 1; j>=0; j--)); do
    global_txt="${global_txt}${globallist[$j]}"
    for ((i=0; i<${#globalportlist[@]}; i+=5)); do
      if [[ ${globalportlist[$i]} == ${globallist[$j]} ]]; then
        # scale from lambda to microns
	pos1=$(echo "${globalportlist[$i+1]}*$scale" | bc -l)
	pos2=$(echo "${globalportlist[$i+2]}*$scale" | bc -l)
	pos3=$(echo "${globalportlist[$i+3]}*$scale" | bc -l)
	pos4=$(echo "${globalportlist[$i+4]}*$scale" | bc -l)
	# get 2 significant decimal places
	pos1=$(echo "scale=2; ${pos1}*100/100" | bc)
	pos2=$(echo "scale=2; ${pos2}*100/100" | bc)
	pos3=$(echo "scale=2; ${pos3}*100/100" | bc)
	pos4=$(echo "scale=2; ${pos4}*100/100" | bc)
	# append 0 to the front if number is 0.66 but written as .66
	if [[ $pos1 == .* ]]; then pos1="0$pos1"; fi
	if [[ $pos2 == .* ]]; then pos2="0$pos2"; fi
	if [[ $pos3 == .* ]]; then pos3="0$pos3"; fi
	if [[ $pos4 == .* ]]; then pos4="0$pos4"; fi
	
	global_txt="$global_txt | $pos1 $pos2 $pos3 $pos4"
      fi
    done
    NEWLINE=$'\n'
    global_txt="$global_txt${NEWLINE}"
  done
  echo "Global ports and positions (microns)" >> $out_file
  echo "$global_txt" >> $out_file
}

# take in cell name (without suffix), and generates .sv and _stim.sv file, assumes port list is available in global variables
generate_sv () {
  local cell=$1
  
  echo "Generating Systemverilog files using ext2svmod... "
  echo "ext2svmod -f -gray \"${inlist[*]}\" $cell" | bash > /dev/null
      
  # add $finish to stimulus
  line='\$stop'
  probe=$(find_line_num_in_file $line ${cell}_stim.sv 0)
  sed -i "${probe}i \$finish;\n" ${cell}_stim.sv
  
  # change sv monitor input and output order to the one specified
  sv_inout=""
  n=$(find_line_num_in_file "monitor" ${cell}_stim.sv 0)
  n=$(( $n + 1 ))
  for ((i=0; i<${#inlist[@]}; i++)); do
    linenum=$(( n + i ))
    line="    ,\"%b\", ${inlist[$i]} ,"
    sed -i "${linenum}s/.*/$line/" ${cell}_stim.sv
  done
      
  n=$(( $n + ${#inlist[@]} ))
  for ((i=0; i<${#outlist[@]}; i++)); do
    linenum=$(( n + i ))
    line="    ,\"%b\", ${outlist[$i]} ,"
    sed -i "${linenum}s/.*/$line/" ${cell}_stim.sv
  done
}

# gets the outputs 
extract_sv_sim_out () {
  local line1="xcelium> run"
  local line2="Simulation complete"
  local n1=$(find_line_num_in_file "\${line1}" xmv_out.txt 0)
  local n2=$(find_line_num_in_file "\${line2}" xmv_out.txt $n1)
  local tokens
      
  # loop through every line with monitored simulation results
  for ((i = $n1 + 1; i < $n2 + $n1; i++)); do
    # tokenize every line using spaces as delimiter
    tokens=( $(sed -n "${i}p" xmv_out.txt) )
	
    # find index in gray code 
    index=0
    for ((j = 0; $j < $inlist_size; j++)); do
      token_index=$(( $inlist_size - $j ))
      inc=$(( ( 2 ** $j ) * ${tokens[$token_index]} ))
      index=$(( $index + $inc ))
    done
    
    # inverse gray code to index truth table output for comparison
    index=$(inverse_gray $index)
      
    for ((k=0; k<${#outlist[@]}; k++)); do
      sv_output[$index,$k]=${tokens[ ${#inlist[@]} + $k + 1]}
    done
  done
}

# generate a 2^n by n gray code matrix 
# $1 inputs the number of columns
generate_gray_code () {
  pow=$((2 ** $1))
  
  # gray(n) = n xor n>>1
  for ((j=0;j<$pow;j++)); do
    gray=$(( $j ^ $j >> 1 ))
    
    #convert number to binary array 
    for ((k=0;k<$1;k++)); do
      gray_bin=$(( ( $gray & ( 1 << $k ) ) >> $k ))
      
      #store in matrix
      gray_bin_mat[$j,$(($1-$k-1))]=${gray_bin}
    done
  done
}

print_gray_mat () {
  for ((i=0;i<$1;i++)); do
    out=""
    for ((j=0;j<$2;j++)); do
        out+="${gray_bin_mat[$i,$j]} "
    done
  echo $out
  done
}

# generate a 2^n by n truth table matrix 
# $1 inputs the number of columns
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

generate_comb_gray_mat () {
  local cell=$1
  local num=$2
  local pow=$((2 ** $num))
  
  #determine edge cases
  if [[ $cell == "inv" ]]; then
    num=1
  fi
  
  # generate gray code input matrix
  gray_bin_mat=()
  generate_gray_code $num
    
  # generate output for each set of inputs and gate
  case $cell in
  inv)
    for ((i=0;i<$pow;i++));do
      gray_bin_mat[$i,1]=$(( ! gray_bin_mat[$i,0] ))
    done
    ;;
  buffer)
    for ((i=0;i<$pow;i++));do
      gray_bin_mat[$i,1]=${gray_bin_mat[$i,0]}
    done
    ;;
  nand)
    for ((i=0;i<$pow;i++));do
      out=1
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out & $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  nor)
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out | $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  and)
    for ((i=0;i<$pow;i++));do
      out=1
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out & $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  or)
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out | $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  xor)
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out ^ $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  xnor)
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out ^ $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  fulladder)
    for ((i=0;i<$pow;i++));do
      # get input (inputs are symmetrical)
      A=${gray_bin_mat[$i,0]}
      B=${gray_bin_mat[$i,1]}
      Cin=${gray_bin_mat[$i,2]}
    
      # full adder logic
      S=$((A ^ B ^ Cin))
      Cout=$(( (A * B) + (Cin * (A ^ B)) ))
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "S" ]]; then 
	  gray_bin_mat[$i,$index]=$S; 
	fi
        if [[ ${outlist[$j]} == "Cout" ]]; then 
	  gray_bin_mat[$i,$index]=$Cout;
	fi
      done
    done
    ;;
  halfadder)
    for ((i=0;i<$pow;i++));do
      # get input (inputs are symmetrical)
      A=${gray_bin_mat[$i,0]}
      B=${gray_bin_mat[$i,1]}
    
      # half adder logic
      S=$((A ^ B))
      C=$((A * B))
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "S" ]]; then 
	  gray_bin_mat[$i,$index]=$S; 
	fi
        if [[ ${outlist[$j]} == "C" ]]; then 
	  gray_bin_mat[$i,$index]=$C;
	fi
      done
    done
    ;;
  mux2)
    for ((i=0;i<$pow;i++));do
      # get input 
      for ((j=0;j<$num;j++));do 
        if [[ ${inlist[$j]} == "I0" ]]; then I0=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "I1" ]]; then I1=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "S" ]]; then S=${gray_bin_mat[$i,$j]}; fi
      done
    
      # mux2 logic
      [[ $S -eq 1 ]] && Y=$I1 || Y=$I0
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "Y" ]]; then
	  gray_bin_mat[$i,$index]=$Y; 
	fi
      done
    done
    ;;
  smux2)
    for ((i=0;i<$pow;i++));do
      # get input 
      for ((j=0;j<$num;j++));do 
        if [[ ${inlist[$j]} == "Test" ]]; then Test=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "SDI" ]]; then SDI=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "D" ]]; then D=${gray_bin_mat[$i,$j]}; fi
      done
    
      # smux2 logic
      [[ $Test -eq 1 ]] && nD=$SDI || nD=$D
      nD=$(( ! $nD ))
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "nD" ]]; then
	  gray_bin_mat[$i,$index]=$nD; 
	fi
      done
    done
    ;;
  smux3)
    for ((i=0;i<$pow;i++));do
      # get input 
      for ((j=0;j<$num;j++));do 
        if [[ ${inlist[$j]} == "Test" ]]; then Test=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "Load" ]]; then Load=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "SDI" ]]; then SDI=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "D" ]]; then D=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "Q" ]]; then Q=${gray_bin_mat[$i,$j]}; fi
      done
    
      # smux3 logic
      [[ $Load -eq 1 ]] && temp=$D || temp=$Q
      [[ $Test -eq 1 ]] && nD=$SDI || nD=$temp
      nD=$(( ! $nD ))
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "nD" ]]; then
	  gray_bin_mat[$i,$index]=$nD; 
	fi
      done
    done
    ;;
  trisbuf)
    for ((i=0;i<$pow;i++));do
      # get input 
      for ((j=0;j<$num;j++));do 
        if [[ ${inlist[$j]} == "Enable" ]]; then Enable=${gray_bin_mat[$i,$j]}; fi
        if [[ ${inlist[$j]} == "A" ]]; then A=${gray_bin_mat[$i,$j]}; fi
      done
    
      # trisbuf logic
      [[ $Enable -eq 1 ]] && Y=$A || Y=z
      
      # print to output matrix
      for ((j=0;j<${#outlist[*]};j++));do 
        index=$(( $j + $num ))
        if [[ ${outlist[$j]} == "Y" ]]; then
	  gray_bin_mat[$i,$index]=$Y; 
	fi
      done
    done
    ;;
  esac
}

# create spice files and measure propagation delay for $cell
# prints simulation parameters and measurements of all iterations to file $1
check_prop_delay () {
  local outfile=$1
  
  # generate spice
  echo Generating SPICE files using ext2sp...
  ext2sp -f $cell > /dev/null
  
  echo "Load capacitances used: ${output_cap[*]}"

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

  # copy current parameters to a temporary file, used in every iteration later on
  cp $cell.sp ${cell}_temp.sp

  # generate truth table 
  generate_truth_table $(( ${#inlist[@]} - 1 ))
  pow=$((2 ** ( ${#inlist[@]} - 1 ) ))

  echo
  echo "Starting simulation..."
  
  for(( i=0; i<${#inlist[@]}; i++)); do
    for(( j=0; j<${#outlist[@]}; j++)); do
      for (( h=0; h<${#output_cap[@]}; h++ )); do
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
      
            index=0
            for(( l=0; l<${#inlist[@]}; l++)); do
              if [[ $l == $i ]]; then
	      
	        # input signal to be tested
                # run two simulations, one with rising edge, one with falling edge
                input="V$l ${inlist[$l]}"
	        if [[ $k -eq 0 ]]; then
                  input="V$i ${inlist[$i]} GND PWL(0NS 0V  5NS 0V  5.175NS ${Vsupply}V)"
                else
                  input="V$i ${inlist[$i]} GND PWL(0NS ${Vsupply}V  5NS ${Vsupply}V  5.175NS 0V)"
                fi
		
              else
	      
	        # other signals
                # generate inputs based on truth table (covers all possiblities)
                [[ ${truth_table[$m,$index]} == 1 ]] && Vin=${Vsupply} || Vin=0
                input="V$l ${inlist[$l]} GND PWL(0NS ${Vin}V)"
	  
                index=$(( $index + 1 ))
              fi
      
              sed -i "$((n+l+4))i $input" $cell.sp
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
    
            # run simulation
            hspice $cell.sp $cell.spice >> /dev/null
	    # cat $cell.mt0
	    echo "SIMPARAM: ${inlist[i]} ${outlist[j]} ${output_cap[h]}" >> $outfile
            cat $cell.mt0 >> $outfile
          done
	  
	  # simulation progress bar
	  local unit4=$(( $i * ${#outlist[@]} * ${#output_cap[@]} * $pow))
          local unit3=$(( $j * ${#output_cap[@]} * $pow))
          local unit2=$(( $h * $pow ))
          local unit1=$m
	  local total=$(( ${#inlist[@]} * ${#outlist[@]} * ${#output_cap[@]} * $pow ))
          percentage=$(( ($unit1 + $unit2 + $unit3 + $unit4) * 100 / $total ))
          echo -ne "Current simulation: ${inlist[i]} -> ${outlist[j]}, load: ${output_cap[h]}  [$percentage%]          \r"
        done
      done
    done
  done
  
  # final simulation progress
  local inout_final="${inlist[${#inlist[@]} - 1]} -> ${outlist[${#outlist[@]} - 1]}"
  local cap_final="${output_cap[${#output_cap[@]} - 1]}"
  echo -ne "Current simulation: $inout_final, load: $cap_final  [100%] \n"
  
  # remove temp file
  rm ${cell}_temp.sp
}

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
      riseValues=(${riseValues[*]} ${k[0]})
      fallValues=(${fallValues[*]} ${k[1]})
      valueFlag=0
    fi
  
    # handle falling input measurements
    if [[ $valueFlag == 2 ]]; then
      riseValues=(${riseValues[*]} ${k[0]})
      fallValues=(${fallValues[*]} ${k[1]})
      valueFlag=0
    fi
  done <"$infile"

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
    
      echo $currentIn $currentOut $currentCap rise:$temp1 fall:$temp2 >> $outfile
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
  
  echo $currentIn $currentOut $currentCap rise:$temp1 fall:$temp2 >> $outfile
  currentIn=${inSignal[$i]}
  currentOut=${outSignal[$i]}
}

check_input_capacitance () {
  local outfile=$1

  # generate spice
  echo "Generating SPICE files using ext2sp..."
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

  echo
  echo "Starting simulation..."

  for(( i=0; i<${#inlist[@]}; i++ )); do
    for (( m=0; m<$pow; m++ )); do
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
      
      index=0
      for(( l=0; l<${#inlist[@]}; l++)); do
        if [[ $l == $i ]]; then
          input="V$l ${inlist[$l]}"
	else
          # generate inputs based on truth table
          [[ ${truth_table[$m,$index]} == 1 ]] && Vin=${Vsupply} || Vin=0
          input="V$l ${inlist[$l]} GND PWL(0NS ${Vin}V)"
	  
          index=$(( $index + 1 ))
	fi
      
        sed -i "$((n+l+4))i $input" $cell.sp
        #echo ${truth_table[$m,$l]} $input
      done
      
      # change the input being tested against to rising or falling edge
      line="V$i"
      n=$(find_line_num_in_file $line $cell.sp 0)
      # run two simulations, one with rising edge, one with falling edge
      input="V$i ${inlist[$i]} GND PWL(0NS 0V  2.5NS 0V  2.675NS ${Vsupply}V 7.5NS ${Vsupply}V  7.675NS 0V)"
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
      #cat $cell.mt0
      echo "SIMPARAM: ${inlist[i]}" >> $outfile
      cat $cell.mt0 >> $outfile
      
      
      unit2=$(( $i * $pow ))
      unit1=$m
      percentage=$(( ($unit1 + $unit2) * 100 / (${#inlist[@]} * $pow) ))
      echo -ne "Current simulation: ${inlist[$i]} [$percentage%]        \r"
    done
  done
  
  # final simulation progress
  local input_final="${inlist[${#inlist[@]} - 1]}"
  echo "Current simulation: $input_final [100%]"
  
  # remove temp file
  rm ${cell}_temp.sp
}

# extract input capacitance from file $1 (a .mt0 file)
# concatenate average of all measurements to file $2
extract_input_capacitance () {
  local infile=$1
  local outfile=$2
  
  # variables to store data read from input file
  local valueFlag=0
  local inSignal=()
  local inCap=()

  while IFS=" " read  -a k; do
    # get measured values (lines after tdfr and tdrr)
    #[[ ${k[*]} =~ ${keys[0]} ]] && echo "flag1"
    #[[ ${k[*]} =~ ${keys[1]} ]] && echo "flag2"
    [[ ${k[*]} =~ "tdavgc" ]] && valueFlag=1 && continue
  
    # get sim parameters
    if [[ "SIMPARAM:" == ${k[0]} ]]; then
      #echo "${k[1]} > ${k[2]}"
      inSignal=(${inSignal[*]} ${k[1]})
    fi
  
    if [[ $valueFlag == 1 ]]; then
      inCap=(${inCap[*]} ${k[1]})
      valueFlag=0
    fi
  done <"$infile"

  # Lists and variables to average all measurements
  local currentIn=${inSignal[0]}
  local currentCap=${inCap[0]}
  local n=0
  local capTotal=0
  
  for ((i=0; i<${#inCap[@]}; i++)); do
    if [[ $currentIn != ${inSignal[$i]} ]]
    then
      # convert to femtofarads unit and take average
      temp=$(echo "${capTotal}/${n}*10^15" | bc -l)
      # shorten the output to 2 decimal precision
      temp=$(echo "scale=2; $temp * 100 / 100" | bc)
    
      echo $currentIn, input capacitance: $temp >> $outfile
      currentIn=${inSignal[$i]}
      currentCap=${inCap[$i]}
      n=0
      capTotal=0
    fi
  
    if [[ ${inCap[$i]} != "failed" ]]; then
      n=$((n + 1))
      # convert riseValue[i] from scientific notation to a decimal number
      temp=$(echo "${inCap[$i]}" | sed -r 's/[e]+/*10^/g' | bc -l)
      # add temp to total
      capTotal=$(echo "${temp}+${capTotal}" | bc -l)
    fi
  done

  # convert to femtofarads unit and take average
  # shorten the output to 2 decimal precision
  temp=$(echo "${capTotal}/${n}*10^15" | bc -l)
  temp=$(echo "scale=2; $temp * 100 / 100" | bc)
    
  echo $currentIn, input capacitance: $temp >> $outfile
}

#------------------------------------- MAIN ----------------------------------------
# clear databook
for entry in *; do
  if [[ $entry == $databook_file ]]; then
    rm $databook_file
  fi
done

if [[ $SIM_ALL -eq 1 ]]; then
  echo "This script is programmed to work properly with the following cells:"
  echo ${comb[*]}
  echo "Errorneous results are to be expected if cells are not in this list"
  echo
elif [[ $SIM_ALL -eq 0 ]]; then
  echo "Generating databook for the following cell library:"
  echo ${cell_lib[*]}
  echo "***Note: Sequential logic is not supported by the script currently"
  echo
fi

# Find the total amount of cells and print all the cells
echo "In the current directory..."
total_cells=0
cell_num=0
sim_cells=()
for entry in *; do
  if [[ "$entry" == *.mag ]]; then
    cell=${entry::-4}
    if [[ $SIM_ALL -eq 1 ]]; then
      total_cells=$(( $total_cells + 1 ))
      echo "Magic cell found $entry"
      sim_cells+=( $cell )
    elif [[ $SIM_ALL -eq 0 && " ${cell_lib[*]} " =~ " ${cell} " ]]; then
      total_cells=$(( $total_cells + 1 ))
      echo "Library cell found $entry"
      sim_cells+=( $cell )
    fi
  fi
done
echo "Total magic cells: $total_cells"
echo 

echo "Generating databook... "
# go through all cells to be simulated
for cell_index in ${sim_cells[@]}; do
  entry=${cell_index}.mag
  
  globallist=()
  inlist=()
  outlist=()
  globalportlist=()
  inportlist=()
  outportlist=()
  ext_file_error_flag=0;
  clockSignal=""
  synchronous_flag=0
  
  #find all magic files in directory
  if [[ "$entry" == *.mag ]]
  then
    #get cell name from magic file
    cell=${entry::-4}
    cell_num=$(( $cell_num + 1 ))
    
    echo
    echo "-----------------------------------------------"
    echo "------------ Current cell: ${cell} ------------"
    echo "-----------------------------------------------"
    echo
    
    echo "Now processing... $cell    ($cell_num of $total_cells)"
    
    echo > magic_out.txt
    # run magic commands
    magic -dnull -noconsole $cell.mag << EOF > magic_out.txt
    extract
    select cell
    box > magic_out.txt
    quit
EOF
# ^^^ this EOF must be not indented...

    # get area
    n=$(find_line_num_in_file "microns:" magic_out.txt 0)
    line=( $(sed -n "${n}p" magic_out.txt) )
    magic_output=${line[1]}
    cell_width=${line[1]}
    cell_height=${line[3]}
    cell_area=${line[(${#line[@]} - 1)]}

    # get boundary in magic units + scale between lambda and microns
    n=$(find_line_num_in_file "lambda:" magic_out.txt 0)
    line=( $(sed -n "${n}p" magic_out.txt) )
    
    # get scale between microns and lambdas
    scale=$(echo "$magic_output/${line[1]}" | bc -l)
    # get cell boundary in lambda units
    magic_output="${line[1]} ${line[3]}"
    
    #check for known cell
    known_flag=0;
    #check if cell is within combinational list
    for str in ${comb[@]}; do
      if [[ $cell == "$str"* ]]; then
        echo "$cell is a known cell..."
	known_flag=1;
	
	celltype=$str
      fi
    done
    
    #check for existence of .ext file for cell
    if ! test -f $cell.ext; then
      echo "**Error** .ext file for \"${cell}\" not found."
      ext_file_error_flag=1;
    fi
    
    
    if [[ $known_flag == 0 ]]; then
      echo "**Warning** cell \"${cell}\" is not a known cell, errorneous values expected..."
    fi
    if [[ $ext_file_error_flag == 0 ]] ; then
      check_in_out $entry $cell.ext ${magic_output[0]} ${magic_output[1]}
      
      echo "Cell: $cell" >> $databook_file
      echo "Cell width: $cell_width (microns)" >> $databook_file
      echo "Cell height: $cell_height (microns)" >> $databook_file
      echo "Cell area: $cell_width * $cell_height = $cell_area (microns^2)" >> $databook_file
      echo >> $databook_file
      echo "Input ports: ${inlist[*]}" >> $databook_file
      echo "Output ports: ${outlist[*]}" >> $databook_file
      echo "Global ports: ${globallist[*]}" >> $databook_file
      echo >> $databook_file
      
      # port position checking
      print_port_pos $databook_file
    
      echo Detected global ports: ${globallist[*]}
      echo Detected input ports: ${inlist[*]}
      echo Detected output ports: ${outlist[*]}
      inlist_size=${#inlist[@]}
      
      # check for clock signal
      synchronous_flag=0
      for ((i=0; i<${#inlist[@]}; i++)); do
        # change string to lowercase
        temp=$(echo "${inlist[$i]}" | tr '[:upper:]' '[:lower:]')
      
        # check if signal is clock/clk 
        if [[ $temp == "clock" || $temp == "clk" ]]; then
	  clockSignal="${inlist[$i]}"
          inlist=( "${inlist[@]/${inlist[$i]}}" )
          echo "Clock signal detected: $clockSignal"
	  
          echo "Clock signal: $clockSignal" >> $databook_file
	  
	  synchronous_flag=1
        fi
      done
      
      # check for errors
      error_flag=0
      # flag no inputs / outputs
      if [[ ${#inlist[@]} -eq 0 ]]; then
        echo "**Error** There are no inputs to this cell"
	error_flag=1
	
	echo "**Cell classification skipped due to input port error" >> $databook_file
      fi
      if [[ ${#outlist[@]} -eq 0 ]]; then
        echo "**Error** There are no outputs to this cell"
	error_flag=1
	
	echo "**Cell classification skipped due to output port error" >> $databook_file
      fi
      
      # skip cells if flagged
      if [[ $synchronous_flag == 1 ]]; then
	echo "*** This script does not support circuits with synchronous inputs... skipping $cell"
	
	cellsSkipped="${cellsSkipped}${cell} "
	
	echo "**Cell classification skipped, sequential logic not supported" >> $databook_file
      fi
      if [[ $error_flag == 1 && ! $synchronous_flag == 1 ]]; then
	echo "*** Error exception, skipping $cell"
	
	cellsSkipped="${cellsSkipped}${cell} "
      fi
      
      if [[ ! $synchronous_flag == 1 && ! $error_flag == 1 ]]; then
      
        echo
        echo "--------- Systemverilog Simulation for ${cell} ---------"
        echo
      
        generate_sv $cell
      
        echo "Simulating $cell via xmverilog..."
        echo "xmverilog ${cell}_stim.sv ${cell}.sv" | bash > xmv_out.txt
        echo
      
        sv_output=()
        extract_sv_sim_out
      
        if [[ known_flag -eq 1 ]]; then
          # generate combinational gray code matrix for known cell
          generate_comb_gray_mat $celltype $inlist_size
      
          correct_flag=1
          for (( i=0; i<2**$inlist_size; i++)); do
	    for (( j=0; j<${#outlist[@]}; j++)); do
	      index=$(( $inlist_size + $j ))
	      known_output=${gray_bin_mat[$i,$index]}
              if [[ ${sv_output[$i,$j]} != $known_output && 
	            $correct_flag != 0 ]]
	      then
	        correct_flag=0
	        echo "Incorrect output detected during SV simulation for $cell"
	      fi
	    done
          done
      
          if [[ $correct_flag == 1 ]]; then
	    # print SV output matrix
	    echo "Simulated input - output matrix:"
	    echo "${inlist[*]} ${outlist[*]}"
	    for (( i=0; i<2**$inlist_size; i++)); do
	      printtext=""
	    
	      # input gray code
	      for (( j=0; j<+${#inlist[@]}; j++)); do
	        printtext="${printtext}${gray_bin_mat[$i,$j]} "
	      done
	    
	      # output from sv
	      for (( j=0; j<+${#outlist[@]}; j++)); do
	        printtext="${printtext}${sv_output[$i,$j]} "
	      done
	      echo $printtext
	    done
            echo "SV simulation completed, output matches known values"
	  else
	    # print expected matrix
	    echo "Expected input - output matrix:"
	    echo "${inlist[*]} ${outlist[*]}"
	    for (( i=0; i<2**$inlist_size; i++)); do
	      printtext=""
	      for (( j=0; j<${#outlist[@]}+${#inlist[@]}; j++)); do
	        printtext="${printtext}${gray_bin_mat[$i,$j]} "
	      done
	      echo $printtext
	    done
	  
	    # print SV output matrix
	    echo "Simulated input - output matrix:"
	    echo "${inlist[*]} ${outlist[*]}"
	    for (( i=0; i<2**$inlist_size; i++)); do
	      printtext=""
	    
	      # input gray code
	      for (( j=0; j<+${#inlist[@]}; j++)); do
	        printtext="${printtext}${gray_bin_mat[$i,$j]} "
	      done
	    
	      # output from sv
	      for (( j=0; j<+${#outlist[@]}; j++)); do
	        printtext="${printtext}${sv_output[$i,$j]} "
	      done
	      echo $printtext
	    done
	    
	    echo "Printing truth table from SV to databook..."
	    # copy outputs from SV simulation
	    for (( i=0; i<2**$inlist_size; i++)); do
	      for (( j=0; j<${#outlist[@]}; j++)); do
	        index=$(( $inlist_size + $j ))
	        gray_bin_mat[$i,$index]=${sv_output[$i,$j]}
	      done
            done
          fi
	
	  # print truth table to databook
	  echo "Truth table:" >> $databook_file
	  echo "${inlist[*]} ${outlist[*]}" >> $databook_file
	  for (( i=0; i<2**$inlist_size; i++)); do
	    #gray code index
	    index=$(( $i ^ $i >> 1 ))
	  
	    printtext=""
	    for (( j=0; j<${#outlist[@]}+${#inlist[@]}; j++)); do
	      printtext="${printtext}${gray_bin_mat[$index,$j]} "
	    done
	    echo $printtext >> $databook_file
	  done
        else
          echo "$cell is not a known cell, truth table generated from SV simulation"
      
          # generate combinational gray code inputs 
          generate_gray_code $inlist_size
	
	  # copy outputs from SV simulation
	  for (( i=0; i<2**$inlist_size; i++)); do
	    for (( j=0; j<${#outlist[@]}; j++)); do
	      index=$(( $inlist_size + $j ))
	      gray_bin_mat[$i,$index]=${sv_output[$i,$j]}
	    done
          done
	
	  # print truth table to databook
	  echo "Truth table:" >> $databook_file
	  echo "${inlist[*]} ${outlist[*]}" >> $databook_file
	  for (( i=0; i<2**$inlist_size; i++)); do
	    #gray code index
	    index=$(( $i ^ $i >> 1 ))
	  
	    printtext=""
	    for (( j=0; j<${#outlist[@]}+${#inlist[@]}; j++)); do
	      printtext="${printtext}${gray_bin_mat[$index,$j]} "
	    done
	    echo $printtext >> $databook_file
	  done
      
	  # print truth table to terminal
          echo "${inlist[*]} ${outlist[*]}"
	  for (( i=0; i<2**$inlist_size; i++)); do
	    #gray code index
	    index=$(( $i ^ $i >> 1 ))
	  
	    printtext=""
	    for (( j=0; j<${#outlist[@]}+${#inlist[@]}; j++)); do
	        printtext="${printtext}${gray_bin_mat[$index,$j]} "
	    done
	    echo $printtext 
	  done
        fi
      
        echo
        echo "--------- SPICE Simulation for ${cell} ---------"
        echo
      
        # clear output file
        echo > "sp_out.txt"
      
        echo >> $databook_file
        echo "Propagation delay (picoseconds)" >> $databook_file
      
        echo "Simulating propagation delay..."
        check_prop_delay "sp_out.txt"
        extract_prop_delay "sp_out.txt" "$databook_file"
      
        # clear output file
        echo > "sp_out.txt"
      
        echo >> $databook_file
        echo "Input capacitances (femtofarads)" >> $databook_file
      
        echo
        echo "Simulating input capacitance..."
        check_input_capacitance "sp_out.txt"
        extract_input_capacitance "sp_out.txt" "$databook_file"
      fi
      
      echo >> $databook_file
      echo "---------------------------------------------------" >> $databook_file
      echo >> $databook_file
      
      
    fi
    echo
    echo "Processing done for ${cell}"
  fi
done

echo 
echo "---------------------------------------------------"
echo
echo "Cells skipped: "
echo "${cellsSkipped[*]}"

echo
echo "Removing simulation files..." 
for entry in *; do
  if [[ $entry != *.mag && \
        $entry != *.sh && \
        $entry != "handin.tar" && \
        $entry != "databook.txt" && \
	$entry != "readme.txt" ]]; then
    echo "rm -r $entry" | bash
  fi
done
