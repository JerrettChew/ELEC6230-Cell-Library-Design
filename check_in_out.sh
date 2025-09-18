NRST=$'initial\n  begin\n    nReset = 1;\n    #1000\n          nReset = 0;\n    #1000\n          nReset = 1;\n  end'

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

check_in_out () {
  # $1 is the .mag file of the cell while $2 is the .ext file

  # test1 finds "<< labels >>" in a magic file, test2 finds next instance of "<<"
  local line1="<< labels >>"
  local line2="<< "
  local n1=$(find_line_num_in_file "\${line1}" $1 0)
  local n2=$(find_line_num_in_file "\${line2}" $1 $n1)
  echo "$entry : <<labels>> $n1 | << $n2"
  
  # loop through every line that specified labels
  for ((i = $n1 + 1 ; i < $n2 + $n1; i++)); do
    # tokenize every line using spaces as delimiter
    tokens=( $(sed -n "${i}p" $1) )
    # add unique tokens to an array, the 7th element always contains the label
    if [[ ! " ${labels[*]} " =~ " ${tokens[7]} " ]]; then
      labels+=(${tokens[7]})
    fi
  done
  
  # find global signal as specified by an ending '!'
  for i in "${labels[@]}"; do
    if [[ $i = *! ]]; then
      globallist+=($i);
    fi
  done
		
  # check source and drain connections
  TEST=$(grep -n "fet" $2 | cut -d "\"" -f 6)
  TEST+=" "$(grep -n "fet" $2 | cut -d "\"" -f 8)
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
  TEST=$(grep -n "fet" $2 | cut -d "\"" -f 4)
  tokens=( $TEST )
  #echo ${tokens[*]}
  for i in "${tokens[@]}"; do
    if [[ (! " ${inlist[*]} " =~ " $i ") && \
          (" ${labels[*]} " =~ " $i ") && \
          (! " ${outlist[*]} " =~ " $i ")]]; then
      inlist+=($i)
    fi
  done
}

# take in cell name (without suffix), and generates .sv and _stim.sv file, assumes port list is available in global variables
generate_sv () {
  local cell=$1
      
  # check for clock signal
  if [[ " ${inlist[*]} " =~ " Clock " ]]; then
    CLOCK="-clock Clock"
    inlist=( "${inlist[@]/Clock}" )
    echo "Clock signal: Clock"
  fi
      
  # check for nReset signal
  if [[ " ${inlist[*]} " =~ " nReset " ]]; then
    NRST_FLAG=1
    inlist=( "${inlist[@]/nReset}" )
    echo "nReset signal: nReset"
  fi
      
  echo "ext2svmod -f $CLOCK -gray \"${inlist[*]}\" $cell" | bash > /dev/null
      
  # modify sv stim file if nrst detected
  if [[ $NRST_FLAG == 1 ]]; then
    probe=$(find_line_num_in_file "probe" ${cell}_stim.sv 0)
	
    # add nReset signals
    sed -i "${probe}i initial\n  begin\n    nReset = 1;\n    #1000\n          nReset = 0;\n    #1000\n          nReset = 1;\n  end\n" ${cell}_stim.sv
    #sed "s/probe/probe\n${NRST}/" ${cell}_stim.sv
    #echo $()
  fi
      
  # add $finish to stimulus
  line='\$stop'
  probe=$(find_line_num_in_file $line ${cell}_stim.sv 0)
  sed -i "${probe}i \$finish;\n" ${cell}_stim.sv
}

# gets the outputs 
extract_sv_sim_out () {
  line1="xcelium> run"
  line2="Simulation complete"
  n1=$(find_line_num_in_file "\${line1}" xmv_out.txt 0)
  n2=$(find_line_num_in_file "\${line2}" xmv_out.txt $n1)
      
  inlist_size=${#inlist[@]}
  # loop through every line with monitored simulation results
  for ((i = $n1 + 1; i < $n2 + $n1; i++)); do
    # tokenize every line using spaces as delimiter
    tokens=( $(sed -n "${i}p" xmv_out.txt) )
    #echo ${tokens[*]}
	
    # find index in gray code 
    index=0
    for ((j = 1; $j <= $inlist_size; j++)); do
      inc=$(( ( 2 ** ($j - 1) ) * ${tokens[$j]} ))
      index=$(( $index + $inc ))
    done
    #echo $index
    
    # inverse gray code to index truth table output for comparison
    index=$(inverse_gray $index)
    sv_output[$index]=${tokens[ ${#tokens[@]} - 1 ]}
  done
}

for entry in *; do
  if [[ $entry == *.mag ]]; then
    cell=${entry::-4}
    ext_file_error_flag=0
    globallist=()
    inlist=()
    outlist=()
    
    if ! test -f $cell.ext; then
      echo "Error: .ext file for \"${cell}\" not found."
      ext_file_error_flag=1;
    fi
    
    if [[ $ext_file_error_flag == 0 ]]; then
      check_in_out $entry $cell.ext
    
      echo $cell
      echo ${globallist[*]}
      echo ${inlist[*]}
      echo ${outlist[*]}
      
      generate_sv $cell
      
      echo "xmverilog ${cell}_stim.sv ${cell}.sv" | bash > xmv_out.txt
      #cat xmv_out.txt
      
      extract_sv_sim_out
      echo ${sv_output[*]}
    fi
    echo "-----------------------------"
  fi
done
