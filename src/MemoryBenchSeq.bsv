package MemoryBenchSeq;

import FIFO :: *;
import SpecialFIFOs :: *;
import GetPut :: *;
import Clocks :: *;
import ClientServer :: *;
import Connectable :: *;
import DefaultValue :: *;
import BUtils :: *;
import DReg :: *;

import BlueAXI :: *;
import BlueLib :: *;

// Configuration Interface
typedef 12 CONFIG_ADDR_WIDTH;
typedef 64 CONFIG_DATA_WIDTH;

// On FPGA Master
typedef 1 FPGA_AXI_ID_WIDTH;
typedef 64 FPGA_AXI_ADDR_WIDTH;
typedef 512 FPGA_AXI_DATA_WIDTH;
typedef 0 FPGA_AXI_USER_WIDTH;


typedef Axi4MasterRead#(FPGA_AXI_ADDR_WIDTH, FPGA_AXI_DATA_WIDTH, FPGA_AXI_ID_WIDTH, FPGA_AXI_USER_WIDTH, 32) TMasterRead;
typedef Axi4MasterWrite#(FPGA_AXI_ADDR_WIDTH, FPGA_AXI_DATA_WIDTH, FPGA_AXI_ID_WIDTH, FPGA_AXI_USER_WIDTH, 32) TMasterWrite;

interface MemoryBenchSeq;
    (*prefix="S_AXI"*) interface AXI4_Lite_Slave_Rd_Fab#(CONFIG_ADDR_WIDTH, CONFIG_DATA_WIDTH) s_rd;
    (*prefix="S_AXI"*) interface AXI4_Lite_Slave_Wr_Fab#(CONFIG_ADDR_WIDTH, CONFIG_DATA_WIDTH) s_wr;

    (*prefix="M_AXI"*) interface AXI4_Master_Rd_Fab#(FPGA_AXI_ADDR_WIDTH, FPGA_AXI_DATA_WIDTH, FPGA_AXI_ID_WIDTH, FPGA_AXI_USER_WIDTH) rd;
    (*prefix="M_AXI"*) interface AXI4_Master_Wr_Fab#(FPGA_AXI_ADDR_WIDTH, FPGA_AXI_DATA_WIDTH, FPGA_AXI_ID_WIDTH, FPGA_AXI_USER_WIDTH) wr;

    (* always_ready *) method Bool interrupt();
endinterface

module mkMemoryBenchSeq#(parameter Bit#(CONFIG_DATA_WIDTH) base_address)(MemoryBenchSeq);

    Integer reg_start = 'h00;
    Integer reg_ret = 'h10;
    /*
        0: Start Sequential Write
        1: Start Sequential Read
        2: Start Sequential Read+Write
    */
    Integer reg_cmd   = 'h20;
    Integer reg_len   = 'h30;

    Reg#(Bool) start <- mkReg(False);
    Reg#(Bool) idle <- mkReg(True);
    Reg#(Bit#(CONFIG_DATA_WIDTH)) status <- mkReg(0);
    Reg#(Bit#(6)) operation <- mkReg(0);
    Reg#(Bit#(CONFIG_DATA_WIDTH)) length <- mkReg(0);

    Wire#(Bool) interrupt_w <- mkDWire(False);

    List#(RegisterOperator#(axiAddrWidth, CONFIG_DATA_WIDTH)) operators = Nil;
    operators = registerHandler(reg_start, start, operators);
    operators = registerHandler(reg_ret, status, operators);
    operators = registerHandler(reg_cmd, operation, operators);
    operators = registerHandler(reg_len, length, operators);
    GenericAxi4LiteSlave#(CONFIG_ADDR_WIDTH, CONFIG_DATA_WIDTH) s_config <- mkGenericAxi4LiteSlave(operators, 1, 1);


    TMasterRead rdMaster <- mkAxi4MasterRead(2, 2, True, 256, True, 2, True);
    TMasterWrite wrMaster <- mkAxi4MasterWrite(2, 2, True, 256, True, 2, True);

    Reg#(UInt#(CONFIG_DATA_WIDTH)) cycleCount <- mkRegU;

    Reg#(Bool) lastCycle <- mkReg(False);

    rule startWrite if(idle && start && operation == 0);
        wrMaster.request.put(AxiRequest {address: 0, bytesToTransfer: cExtend(length), region: 0});
        start <= False;
        idle <= False;
        lastCycle <= False;
        cycleCount <= 0;
    endrule

    rule startRead if(idle && start && operation == 1);
        rdMaster.server.request.put(AxiRequest {address: 0, bytesToTransfer: cExtend(length), region: 0});
        start <= False;
        idle <= False;
        lastCycle <= False;
        cycleCount <= 0;
    endrule

    rule startReadWrite if(idle && start && operation == 2);  
        rdMaster.server.request.put(AxiRequest {address: length, bytesToTransfer: cExtend(length), region: 0});
        wrMaster.request.put(AxiRequest {address: 0, bytesToTransfer: cExtend(length), region: 0});
        start <= False;
        idle <= False;
        lastCycle <= False;
        cycleCount <= 0;
    endrule

    Reg#(Bool) interruptR <- mkDReg(False);

    rule dropReads;
        let r <- rdMaster.server.response.get();
    endrule

    rule insertWrites;
        wrMaster.data.put(
        'hDEAFBEEFDEADBEFFDEADBEFFDEAFBEEFDEADBEFFDEADBEFFDEAFBEEFDEADBEFFDEADBEFFDEAFBEEFDEADBEFFDEADBEFFDEAFBEEFDEADBEFFDEADBEFFDEAFBEEF);
    endrule

    rule checkActivity if(!idle);
        let cur = ?;
        if(operation == 0) begin
            cur = wrMaster.active;
        end else if(operation == 1) begin
            cur = rdMaster.active;
        end else if(operation == 2) begin
            cur = wrMaster.active || rdMaster.active;
        end
        cycleCount <= cycleCount + 1;
        lastCycle <= cur;
        if(!cur && lastCycle) begin
            idle <= True;
            status <= pack(cycleCount);
            interruptR <= True;
        end
    endrule

    interface s_rd = s_config.s_rd;
    interface s_wr = s_config.s_wr;

    interface rd = rdMaster.fab;
    interface wr = wrMaster.fab;

    method Bool interrupt = interruptR;
endmodule

endpackage
