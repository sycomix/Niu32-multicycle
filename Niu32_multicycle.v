module Niu32_multicycle(SWITCH, KEY, LEDR, LEDG, HEX0, HEX1, HEX2, HEX3, CLOCK_50);
    input  [9:0] SWITCH;
    input  [3:0] KEY;
    input  CLOCK_50;
    output [9:0] LEDR;
    output [7:0] LEDG;
    output [6:0] HEX0, HEX1, HEX2, HEX3;
    
    // 32-bit initialization
    parameter WORD_SIZE = 32; // In bits.
    parameter INSTR_SIZE = 4; // In bytes. Used to increment PC.
    parameter IMM_SIZE = 17; // Size of immediate value, in bits.
    parameter NUM_REGS = 32; // Number of registers.
    parameter REG_BITS = 5; // Number of selector bits for register file.
    parameter OP_BITS = 5; // Number of selector bits for the opcode.
    parameter STATE_BITS = 6; // Number of bits for the state machine.
    
    // I/O memory locations
    parameter ADDR_HEX = 32'hFFFF0000; // Memory location of hex lights on board.
    parameter ADDR_LEDR = 32'hFFFF0020; // Memory location of red LED lights on board.
    parameter ADDR_LEDG = 32'hFFFF0040; // Memory location of green LED lights on board.
    parameter ADDR_KEY = 32'hFFFF0100; // Memory location to access key states on board.
    parameter ADDR_SWITCH = 32'hFFFF0120; // Memory location to access switch states on board.
    
    // Init
    parameter INIT_MIF = "test1.mif"; // IMPORTANT! Point this to assembled Niu32 MIF!
    parameter IMEM_WORDS = 2048; // Max number of words in instruction memory.
    parameter DMEM_WORDS = 2048; // Max number of words in data memory.
    parameter MEM_ADDR_BITS = 13; // Number of bits used for indexing into memory.
    parameter MEM_WORD_OFFSET = 2; // Number of bits used for selecting individual memory words.
    parameter PC_STARTLOC = 32'h0; // Starting value of PC.

    // Other
    parameter BUS_NOSIG = {WORD_SIZE {1'bZ}}; // Default block signal on bus
    parameter BYTE_SEL_MASK = {WORD_SIZE {1'b0}} + {(WORD_SIZE / 4) {1'b1}}; // Mask to select byte in SB/LB instr
    
    // Control signals
    reg LdPC, DrPC, IncPC;
    reg WrMem, DrMem, LdMAR;
    reg WrReg, DrReg;
    reg LdIR;
    reg DrImm, ShImm; // ShImm = DrImm with Imm * INSTR_SIZE
    reg LdA, LdB, DrALU;
    
    /// Opcodes
    // Primary
    parameter OP1_ALUI = 5'b00000;
    parameter OP1_ADDI = 5'b00001;
    parameter OP1_MLTI = 5'b00010;
    parameter OP1_DIVI = 5'b00011;
    parameter OP1_ANDI = 5'b00101;
    parameter OP1_ORI = 5'b00110;
    parameter OP1_XORI = 5'b00111;
    parameter OP1_SULI = 5'b01000;
    parameter OP1_SSLI = 5'b01001;
    parameter OP1_SURI = 5'b01010;
    parameter OP1_SSRI = 5'b01011;
    parameter OP1_LW = 5'b10000;
    parameter OP1_LB = 5'b10001;
    parameter OP1_SW = 5'b10011;
    parameter OP1_SB = 5'b10100;
    parameter OP1_LUI = 5'b10110;
    parameter OP1_BEQ = 5'b11000;
    parameter OP1_BNE = 5'b11001;
    parameter OP1_BLT = 5'b11010;
    parameter OP1_BLE = 5'b11011;
    parameter OP1_JAL = 5'b11111;
    
    // Secondary
    parameter OP2_SUB = 5'b00000;
    parameter OP2_ADD = 5'b00001;
    parameter OP2_MLT = 5'b00010;
    parameter OP2_DIV = 5'b00011;
    parameter OP2_NOT = 5'b00100;
    parameter OP2_AND = 5'b00101;
    parameter OP2_OR = 5'b00110;
    parameter OP2_XOR = 5'b00111;
    parameter OP2_SUL = 5'b01000;
    parameter OP2_SSL = 5'b01001;
    parameter OP2_SUR = 5'b01010;
    parameter OP2_SSR = 5'b01011;
    parameter OP2_EQ = 5'b10000;
    parameter OP2_NEQ = 5'b10001;
    parameter OP2_LT = 5'b10010;
    parameter OP2_LEQ = 5'b10011;
    
    // Other signals
    parameter OP3_LUI = 5'b11100;
    parameter OP3_BITSEL = 5'b11101;
    parameter OP3_BITUNSET = 5'b11110;
    parameter OP3_BITSET = 5'b11111;
    
    // Init clock signal, lock signal
    
    wire clk, lock;
    reg clkReg, numEdges, resetReg;
    assign clk = CLOCK_50;
    
    always @(posedge clk) begin
        if (resetReg)
            resetReg = 0;
    end
    
    initial begin
        resetReg = 1;
    end
    
    //ClockDivider clkdiv(.clkIn(CLOCK_50), .clkOut(clk)); // Opposite of a PLL?
    //Pll pll(.inclk0(CLOCK_50), .c0 (clk), .locked (lock));
    //wire clk = !KEY[0];
    //wire reset = !lock;
    //wire reset = KEY[1];
    //wire reset = !KEY[0]; // Reset key
    wire reset = resetReg;
    
    // Define I/O
    reg [(WORD_SIZE - 1):0] HEXout, LEDRout, LEDGout, KEYout, SWITCHout;
    assign LEDR = LEDRout[9:0];
    assign LEDG = LEDGout[7:0];
    
    // Init seven-segment display
    SevenSeg Hex0Out(.hexNumIn(HEXout[3:0]), .displayOut(HEX0));
    SevenSeg Hex1Out(.hexNumIn(HEXout[7:4]), .displayOut(HEX1));
    SevenSeg Hex2Out(.hexNumIn(HEXout[11:8]), .displayOut(HEX2));
    SevenSeg Hex3Out(.hexNumIn(HEXout[15:12]), .displayOut(HEX3));
	 
    // Create bus
    tri [(WORD_SIZE - 1):0] bus;
    
    // Create PC
    reg [(WORD_SIZE - 1):0] PC; // Program counter register.
    
    // PC logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // If we're given the reset signal, reset the PC to the start.
            PC <= PC_STARTLOC;
        end else if (LdPC) begin
            // If LdPC, grab the PC value from the bus.
            PC <= bus;
        end else if (IncPC) begin
            // Otherwise, increment the PC to the next instruction.
            PC <= PC + INSTR_SIZE;
        end
    end
    
    // Hook up PC to bus
    assign bus = DrPC ? PC : BUS_NOSIG;
    
	 // TODO: FOR NOW, THIS IS A MEMORY!!
    // Register file
    reg [(WORD_SIZE - 1):0] regFile [(NUM_REGS - 1):0];
    reg [(REG_BITS - 1):0] regSel; // Register selector
    
    always @(posedge clk) begin
        if (WrReg && lock) begin
            regFile[regSel] <= bus;
        end
    end
    
    // Hook up register file to bus
    wire [(WORD_SIZE - 1):0] regOut = WrReg ? BUS_NOSIG : regFile[regSel];
    assign bus = DrReg ? regOut : BUS_NOSIG;
    
    // Instruction memory
    (* ram_init_file = INIT_MIF *)
    reg [(WORD_SIZE - 1):0] imem[(IMEM_WORDS - 1):0];
    reg [(WORD_SIZE - 1):0] IR; // Instruction register
    wire [(WORD_SIZE - 1):0] imemOutput = imem[PC[(MEM_ADDR_BITS - 1):MEM_WORD_OFFSET]];
    
    // Data memory
    (* ram_init_file = INIT_MIF *)
    reg [(WORD_SIZE - 1):0] dmem[(DMEM_WORDS - 1):0];
    reg [(WORD_SIZE - 1):0] MAR, MDR;
    wire [(WORD_SIZE - 1):0] dmemOutput = WrMem ? BUS_NOSIG : MDR;
    
    // Hook up MAR to MDR and update each clock
    always @(posedge clk) begin
        if (reset) begin
            MAR <= {WORD_SIZE{1'bX}};
            MDR <= {WORD_SIZE{1'bX}};
        end else begin
            if (LdMAR) begin
                MAR <= bus;
            end
            
            // Push iMem instruction to IR on each clock
            if (LdIR) begin
                IR = imemOutput;
            end
            
            if (WrMem && !reset) begin
                if (MAR == ADDR_HEX) begin
                    HEXout <= bus;
                end else if (MAR == ADDR_LEDG) begin
                    LEDGout <= bus;
                end else if (MAR == ADDR_LEDR) begin
                    LEDRout <= bus;
                end else begin
                    dmem[(MAR[(MEM_ADDR_BITS - 1):0] >> MEM_WORD_OFFSET)] <= bus;
                end
            end
            
            if (MAR == ADDR_KEY) begin
                MDR <= {28'b0, KEY};
            end else if (MAR == ADDR_SWITCH) begin
                MDR <= {12'b0, SWITCH}; 
            end else begin
                MDR <= dmem[(MAR[(MEM_ADDR_BITS - 1):0] >> MEM_WORD_OFFSET)];
            end
        end
    end
    
    // Hook up data memory to bus
    assign bus = DrMem ? dmemOutput : BUS_NOSIG;

    // ALU
    reg [(WORD_SIZE - 1):0] A, B, ALUout;
    reg [(OP_BITS - 1):0] ALUfunc;
    reg [(WORD_SIZE - 1):0] setReg; // For SB
    
    // Actual ALU logic
    always @(posedge clk) begin
        if (LdA) begin
            A <= bus;
        end else if (LdB) begin
            B <= bus;
        end
        
        case (ALUfunc)
            OP2_SUB: ALUout = (A - B);
            OP2_ADD: ALUout = (A + B);
            OP2_MLT: ALUout = (A * B);
            OP2_DIV: ALUout = (A / B);
            OP2_NOT: ALUout = ~A;
            OP2_AND: ALUout = (A & B);
            OP2_OR: ALUout = (A | B);
            OP2_XOR: ALUout = (A ^ B);
            OP2_SUL: ALUout = (A << B);
            OP2_SSL: ALUout = (A <<< B);
            OP2_SUR: ALUout = (A >> B);
            OP2_SSR: ALUout = (A >>> B);
            OP2_EQ: ALUout = (A == B);
            OP2_NEQ: ALUout = (A != B);
            OP2_LT: ALUout = (A < B);
            OP2_LEQ: ALUout = (A <= B);
            OP3_LUI: ALUout = (A & (B << 23));
            OP3_BITSEL: ALUout = ((A & (BYTE_SEL_MASK << (24 - (B * 8)))) >> (24 - (B * 8)));
            OP3_BITUNSET: begin
                setReg <= B;
                ALUout = (A & (~BYTE_SEL_MASK << (24 - (B * 8))));
            end
            OP3_BITSET: ALUout = (A | setReg << (24 - (setReg * 8)));
            default: ALUout = BUS_NOSIG;
        endcase
    end
    
    // Hook up ALU to bus
    assign bus = DrALU ? ALUout : BUS_NOSIG;
    
    // Instruction parsing
    wire [(OP_BITS - 1):0] op1, op2;
    wire [(REG_BITS - 1):0] rx, ry, rz;
    wire [(IMM_SIZE - 1):0] imm;
    
    // Below is parameterized assuming 32-bit
    assign op1 = IR[31:27];
    assign rx = IR[26:22];
    assign ry = IR[21:17];
    assign rz = IR[16:12];
    assign imm = IR[16:0];
    assign op2 = IR[4:0];
    
    wire [(WORD_SIZE - 1):0] immOut;
	 SXT ExtendImmTo32(.IN(imm), .OUT(immOut));
	 // If(DrImm) drive val onto bus; else if(ShImm) drive val*instrsize onto bus
	 assign bus = DrImm ? immOut : (ShImm ? (immOut * INSTR_SIZE) : BUS_NOSIG);
	 
    // State machine
    reg [(STATE_BITS - 1):0] state, nextState;
    
    parameter [(STATE_BITS - 1):0] 
        S_FETCH = {(STATE_BITS) {1'b0}},
        S_DECODE = S_FETCH + 1'b1,
        S_ALU0I = S_DECODE + 1'b1,
        S_ALU0R = S_ALU0I + 1'b1,
        S_ALU1 = S_ALU0R + 1'b1,
        S_ALU2 = S_ALU1 + 1'b1,
        S_ALU3 = S_ALU2 + 1'b1,
        S_LW0 = S_ALU3 + 1'b1,
        S_LW1 = S_LW0 + 1'b1,
        S_LW2 = S_LW1 + 1'b1,
        S_LW3 = S_LW2 + 1'b1,
        S_LB0 = S_LW3 + 1'b1,
        S_LB1 = S_LB0 + 1'b1,
        S_LB2 = S_LB1 + 1'b1,
        S_LB3 = S_LB2 + 1'b1,
        S_SW0 = S_LB3 + 1'b1,
        S_SW1 = S_SW0 + 1'b1,
        S_SW2 = S_SW1 + 1'b1,
        S_SW3 = S_SW2 + 1'b1,
        S_SB0 = S_SW3 + 1'b1,
        S_SB1 = S_SB0 + 1'b1,
        S_SB2 = S_SB1 + 1'b1,
        S_SB3 = S_SB2 + 1'b1,
        S_SB4 = S_SB3 + 1'b1,
        S_SB5 = S_SB4 + 1'b1,
        S_LUI0 = S_SB5 + 1'b1,
        S_LUI1 = S_LUI0 + 1'b1,
        S_LUI2 = S_LUI1 + 1'b1,
        S_BRCH0 = S_LUI2 + 1'b1,
        S_BRCH1 = S_BRCH0 + 1'b1,
        S_BRCH2 = S_BRCH1 + 1'b1,
        S_BRCH3 = S_BRCH2 + 1'b1,
        S_BRCH4 = S_BRCH3 + 1'b1,
        S_BRCH5 = S_BRCH4 + 1'b1,
        S_JUMP0 = S_BRCH5 + 1'b1,
        S_JUMP1 = S_JUMP0 + 1'b1,
        S_ERROR = 6'b111111;
    
    parameter ON = 1'b1;
    parameter OFF = 1'b0;
    
    always @(posedge clk) begin
        {LdPC, DrPC, IncPC} = {OFF, OFF, OFF};
        {WrMem, DrMem, LdMAR} = {OFF, OFF, OFF};
        {WrReg, DrReg, regSel} = {OFF, OFF, {(REG_BITS) {1'b0}}};
        LdIR = OFF;
        {DrImm, ShImm} = OFF;
        {LdA, LdB, DrALU, ALUfunc} = {OFF, OFF, OFF, {(OP_BITS) {1'b0}}};
        state = nextState;
        
        if (reset) begin
            state = S_FETCH;
        end
        
        case (state)
            S_FETCH: begin
                {LdIR, IncPC} = {ON, ON};
                nextState = S_DECODE;
            end
            
            S_DECODE: begin
                case (op1)
                    OP1_ALUI: begin
                        nextState = S_ALU0R;
                    end
                    
                    OP1_ADDI, OP1_MLTI, OP1_DIVI, 
                    OP1_ANDI, OP1_ORI, OP1_XORI, 
                    OP1_SULI, OP1_SSLI, OP1_SURI, OP1_SSRI: begin
                        nextState = S_ALU0I;
                    end
                    
                    OP1_LW: begin
                        nextState = S_LW0;
                    end
                    
                    OP1_LB: begin
                        nextState = S_LB0;
                    end
                    
                    OP1_SW: begin
                        nextState = S_SW0;
                    end
                    
                    OP1_SB: begin
                        nextState = S_SB0;
                    end
                    
                    OP1_LUI: begin
                        nextState = S_LUI0;
                    end
                    
                    OP1_BEQ, OP1_BNE, OP1_BLT, OP1_BLE: begin
                        nextState = S_BRCH0;
                    end
                    
                    OP1_JAL: begin
                        nextState = S_JUMP0;
                    end
                endcase
            end

            S_ALU0I: begin
                // ALU op: Immediate version
                {DrImm, LdB} = {ON, ON};
                nextState = S_ALU1;
            end
            
            S_ALU0R: begin
                // ALU op: register version
                {regSel, DrReg, LdB} = {ry, ON, ON};
                nextState = S_ALU1;
            end
            
            S_ALU1: begin
                {regSel, DrReg, LdA} = {rx, ON, ON};
                nextState = S_ALU2;
            end
            
            S_ALU2: begin
                if (op1 == OP1_ALUI) begin
                    {ALUfunc, regSel} = {op2, rz};
                end else begin
                    {ALUfunc, regSel} = {op1, ry};
                end
                
                {regSel, DrALU, WrReg} = {rz, ON, ON};
                nextState = S_FETCH;
            end
            
            S_LW0: begin
                {regSel, LdA, DrReg} = {rx, ON, ON};
                nextState = S_LW1;
            end
            
            S_LW1: begin
                {LdB, DrImm} = {ON, ON};
                nextState = S_LW2;
            end
            
            S_LW2: begin
                {ALUfunc, DrALU, LdMAR} = {OP2_ADD, ON, ON};
                nextState = S_LW3;
            end
            
            S_LW3: begin
                {regSel, WrReg, DrMem} = {ry, ON, ON};
                nextState = S_FETCH;
            end
            
            S_LB0: begin
                {regSel, LdMAR, DrReg} = {rx, ON, ON};
                nextState = S_LB1;
            end
            
            S_LB1: begin
                {LdA, DrMem} = {ON, ON};
                nextState = S_LB2;
            end
            
            S_LB2: begin
                {LdB, DrImm} = {ON, ON};
                nextState = S_LB3;
            end
            
            S_LB3: begin
                {ALUfunc, regSel, DrALU, WrReg} = {OP3_BITSEL, ry, ON, ON};
                nextState = S_FETCH;
            end

            S_SW0: begin
                {regSel, LdA, DrReg} = {rx, ON, ON};
                nextState = S_SW1;
            end

            S_SW1: begin
                {LdB, DrImm} = {ON, ON};
                nextState = S_SW2;
            end

            S_SW2: begin
                {ALUfunc, DrALU, LdMAR} = {OP2_ADD, ON, ON};
                nextState = S_SW3;
            end

            S_SW3: begin
                {regSel, WrMem, DrReg} = {ry, ON, ON};
                nextState = S_FETCH;
            end

            S_SB0: begin
                {regSel, LdMAR, DrReg} = {rx, ON, ON};
                nextState = S_SB1;
            end

            S_SB1: begin
                {LdA, DrMem} = {ON, ON};
                nextState = S_SB2;
            end

            S_SB2: begin
                {LdB, DrImm} = {ON, ON};
                nextState = S_SB3;
            end

            S_SB3: begin
                {ALUfunc, LdA, DrALU} = {OP3_BITUNSET, ON, ON};
                nextState = S_SB4;
            end

            S_SB4: begin
                {regSel, LdB, DrReg} = {ry, ON, ON};
                nextState = S_SB5;
            end

            S_SB5: begin
                {ALUfunc, WrMem, DrALU} = {OP3_BITSET, ON, ON};
                nextState = S_FETCH; 
            end
            
            S_LUI0: begin
                {regSel, LdA, DrReg} = {ry, ON, ON};
                nextState = S_LUI1;
            end
            
            S_LUI1: begin
                {LdB, DrImm} = {ON, ON};
                nextState = S_LUI2;
            end
            
            S_LUI2: begin
                {ALUfunc, regSel, WrReg} = {OP3_LUI, rz, ON};
                nextState = S_FETCH;
            end
            
            S_BRCH0: begin
                {regSel, LdA, DrReg} = {rx, ON, ON};
                nextState = S_BRCH1;
            end
            
            S_BRCH1: begin
                {regSel, LdB, DrReg} = {ry, ON, ON};
                nextState = S_BRCH2;
            end
            
            S_BRCH2: begin
                case (op1)
                    OP1_BEQ: ALUfunc = OP2_EQ;
                    OP1_BNE: ALUfunc = OP2_NEQ;
                    OP1_BLT: ALUfunc = OP2_LT;
                    OP1_BLE: ALUfunc = OP2_LEQ;
                    default: ALUfunc = OP2_EQ;
                endcase
                
                if (ALUout) begin
                    // Take the branch!
                    nextState = S_BRCH3;
                end else begin
                    // Don't take the branch
                    nextState = S_FETCH;
                end
            end
            
            S_BRCH3: begin
                {LdA, DrPC} = {ON, ON};
                nextState = S_BRCH4;
            end
            
            S_BRCH4: begin
                {LdB, ShImm} = {ON, ON};
                nextState = S_BRCH5;
            end
            
            S_BRCH5: begin
                {ALUfunc, LdPC, DrALU} = {OP2_ADD, ON, ON};
                nextState = S_FETCH;
            end
            
            S_JUMP0: begin
                {regSel, WrReg, DrPC} = {ry, ON, ON};
                nextState = S_JUMP1;
            end
            
            S_JUMP1: begin
                {regSel, LdPC, DrReg} = {rx, ON, ON};
                nextState = S_FETCH;
            end
            
            S_ERROR: begin
                // Remain in error state
                nextState = S_ERROR;
            end
        endcase
    end
    
    
endmodule
