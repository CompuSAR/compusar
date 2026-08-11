interface sync_bus #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
);
  logic req_valid;                                       // 
  logic [ADDR_WIDTH-1:0] req_addr;                       // 
  logic [DATA_WIDTH-1:0] req_data;                       // 
  logic req_ack;                                         // 
  logic req_write;                                       // 
  logic rsp_valid;                                       // 
  logic [DATA_WIDTH-1:0] rsp_data;                       // 

  modport MASTER (
    input req_ack, rsp_valid, rsp_data, 
    output req_valid, req_addr, req_data, req_write
    );

  modport SLAVE (
    input req_valid, req_addr, req_data, req_write, 
    output req_ack, rsp_valid, rsp_data
    );

  modport MONITOR (
    input req_valid, req_addr, req_data, req_ack, req_write, rsp_valid, rsp_data
    );

endinterface // sync_bus

interface sync_bus_write_mask #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
);
  logic req_valid;                                       // 
  logic [ADDR_WIDTH-1:0] req_addr;                       // 
  logic [DATA_WIDTH-1:0] req_data;                       // 
  logic req_ack;                                         // 
  logic [(DATA_WIDTH/8)-1:0] req_write_mask;             // 
  logic rsp_valid;                                       // 
  logic [DATA_WIDTH-1:0] rsp_data;                       // 

  modport MASTER (
    input req_ack, rsp_valid, rsp_data, 
    output req_valid, req_addr, req_data, req_write_mask
    );

  modport SLAVE (
    input req_valid, req_addr, req_data, req_write_mask, 
    output req_ack, rsp_valid, rsp_data
    );

  modport MONITOR (
    input req_valid, req_addr, req_data, req_ack, req_write_mask, rsp_valid, rsp_data
    );

endinterface // sync_bus
