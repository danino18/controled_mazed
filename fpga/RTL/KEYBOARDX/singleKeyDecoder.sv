// (c) Technion IIT, Department of Electrical Engineering 2021 
// Written By David Bar-On  June 2018 
// detect a key and generate three ouptputs for this key 


module singleKeyDecoder 	
 ( 
   input	 logic      clk,
	input	 logic      resetN, 
   input  logic[8:0]	keyCode,	
   input  logic 	   make,	
   input  logic 	   brakee,  // warning "break" is a reserved SYSVerilog word 
	
   output logic  keyLatch, // toggle this output every time the key is pressed   
   output logic  keyRisingEdgePulse, // valid for one clock after presing the key 
   output logic  keyIsPressed	// valid while the key is pressed
 	 
  ) ;

   parameter KEY_VALUE = 9'h070 ; // zero is the default 
 	
	logic keyIsPressed_d ; //  _d == delay of one clock 
 
   assign keyRisingEdgePulse = ( keyIsPressed_d == 1'b0 ) && ( keyIsPressed == 1'b1 ) ; // detects a rising edge (change) in the input
 
  	always_ff @(posedge clk or negedge resetN)
		begin: fsm_sync_proc
			if (resetN == 1'b0) begin 
				keyIsPressed_d <= 0  ; 
				keyIsPressed  <= 0 ; 
				keyLatch <= 0 ;
	 
			end 
//--------------------------------------------------------------
// &&&&&&&&&&&&&& fill your code and paste to the report #1 
//--------------------------------------------------------------				
			else begin 
			   if (keyCode  == KEY_VALUE ) begin
				
						if(make)
						keyIsPressed <= 1'b1;
						
						else if(brakee)
						keyIsPressed <= 1'b0;
						
					
				end  
				 
				keyIsPressed_d  <= keyIsPressed ; // generate a delay of one clock 
				keyLatch <= ( keyRisingEdgePulse ) ? ~keyLatch : keyLatch ; // toggle every rising edge 
		
			end // if 
//-------------------------------------------------------------
// &&&&&&&&&&&&&&  end of paste to the report #1 
//-------------------------------------------------------------			
	end // always_ff 

endmodule


