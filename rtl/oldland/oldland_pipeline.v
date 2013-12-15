module oldland_pipeline(input wire		clk,
			input wire		irq_req,
			/* Instruction bus. */
			output wire		i_access,
			output wire [29:0]	i_addr,
			input wire [31:0]	i_data,
			input wire		i_ack,
			input wire		i_error,
			/* Data bus. */
			output wire [29:0]	d_addr,
			output wire [3:0]	d_bytesel,
			output wire		d_wr_en,
			output wire [31:0]	d_wr_val,
			input wire [31:0]	d_data,
			output wire		d_access,
			input wire		d_ack,
			input wire		d_error,
			/* Debug signals. */
			input wire		run,
			output wire		stopped,
			output wire		running,
			output wire		bkpt_hit,
			/* Memory debug. */
			input wire [31:0]	dbg_mem_addr,
			input wire [1:0]	dbg_mem_width,
			input wire [31:0]	dbg_mem_wr_val,
			output wire [31:0]	dbg_mem_rd_val,
			input wire		dbg_mem_wr_en,
			input wire		dbg_mem_access,
			output wire		dbg_mem_compl,
			/* Register access. */
			input wire [3:0]	dbg_reg_sel,
			input wire [31:0]	dbg_reg_wr_val,
			output wire [31:0]	dbg_reg_val,
			input wire		dbg_reg_wr_en,
			input wire [2:0]	dbg_cr_sel,
			output wire [31:0]	dbg_cr_val,
			input wire [31:0]	dbg_cr_wr_val,
			input wire		dbg_cr_wr_en,
			output wire [31:0]	dbg_pc,
			input wire [31:0]	dbg_pc_wr_val,
			input wire		dbg_pc_wr_en,
			/* Reset. */
			input wire		dbg_rst,
			/* CPUID> */
			output wire [2:0]	cpuid_sel,
			input wire [31:0]	cpuid_val);

/* Fetch -> decode signals. */
wire [31:0]	fd_pc_plus_4;
wire [31:0]	fd_instr;
wire		fd_exception_start;
wire		fd_i_fetched;
wire		fe_disable_irqs;
wire		fe_irq_start;
wire [31:0]	fe_irq_fault_address;

/* Execute -> fetch signals. */
wire		ef_branch_taken;
wire		ef_stall_clear;

/* Decode signals. */
wire [3:0]	d_ra_sel;
wire [3:0]	d_rb_sel;

reg [3:0]	e_ra_sel = 4'b0;
reg [3:0]	e_rb_sel = 4'b0;

/* Decode -> execute signals. */
wire [3:0]	de_rd_sel;
wire		de_update_rd;
wire [31:0]	de_imm32;
wire [4:0]	de_alu_opc;
wire [2:0]	de_branch_condition;
wire		de_alu_op1_ra;
wire		de_alu_op1_rb;
wire		de_alu_op2_rb;
wire		de_mem_load;
wire		de_mem_store;
wire [31:0]	ra;
wire [31:0]	rb;
wire [31:0]	de_pc_plus_4;
wire [1:0]	de_class;
wire		de_is_call;
wire [1:0]	de_mem_width;
wire		de_update_flags;
wire		de_update_carry;
wire [2:0]      de_cr_sel;
wire            de_write_cr;
reg [31:0]	de_ra = 32'b0;
reg [31:0]	de_rb = 32'b0;
wire            de_is_swi;
wire            de_is_rfe;
wire		df_illegal_instr;
wire		de_exception_start;
wire		de_i_valid;

/* Execute -> memory signals. */
wire [31:0]	em_alu_out;
wire		em_mem_load;
wire		em_mem_store;
wire		em_update_rd;
wire [3:0]	em_rd_sel;
wire [31:0]	em_wr_val;
wire [1:0]	em_mem_width;
wire [31:0]	em_mar;
wire [31:0]	em_mdr;
wire		em_mem_wr_en;
wire [31:0]	em_pc_plus_4;
wire [25:0]	e_vector_base;
wire		em_i_valid;
wire		m_busy; /* Memory/writeback busy. */
wire		ei_irqs_enabled;

/* Memory -> writeback signals. */
wire [31:0]	mw_wr_val;
wire		mw_update_rd;
wire [3:0]	mw_rd_sel;
wire		mf_complete;
wire		m_data_abort;

/* Fetch stalling signals. */
wire		stall_clear = ef_stall_clear | mf_complete;
wire		stalling;

assign		running = run;

wire		pipeline_busy = fd_i_fetched | de_i_valid | em_i_valid | m_busy;

oldland_fetch	fetch(.clk(clk),
		      .rst(dbg_rst),
		      .irq_req(irq_req),
		      .i_access(i_access),
		      .i_ack(i_ack),
		      .i_error(i_error),
		      .stall_clear(stall_clear),
		      .branch_pc(em_alu_out),
		      .branch_taken(ef_branch_taken),
		      .pc_plus_4(fd_pc_plus_4),
		      .instr(fd_instr),
		      .fetch_addr(i_addr),
		      .fetch_data(i_data),
		      .run(run),
		      .stopped(stopped),
		      .dbg_pc(dbg_pc),
		      .dbg_pc_wr_en(dbg_pc_wr_en),
		      .dbg_pc_wr_val(dbg_pc_wr_val),
		      .illegal_instr(df_illegal_instr),
		      .vector_base(e_vector_base),
		      .data_abort(m_data_abort),
		      .exception_start(fd_exception_start),
		      .i_fetched(fd_i_fetched),
		      .pipeline_busy(pipeline_busy),
		      .irqs_enabled(ei_irqs_enabled),
		      .decode_exception(de_exception_start),
		      .exception_disable_irqs(fe_disable_irqs),
		      .irq_start(fe_irq_start),
		      .irq_fault_address(fe_irq_fault_address),
		      .bkpt_hit(bkpt_hit));

oldland_decode	decode(.clk(clk),
		       .rst(dbg_rst),
		       .instr(fd_instr),
		       .ra_sel(d_ra_sel),
		       .rb_sel(d_rb_sel),
		       .rd_sel(de_rd_sel),
		       .update_rd(de_update_rd),
		       .imm32(de_imm32),
		       .alu_opc(de_alu_opc),
		       .branch_condition(de_branch_condition),
		       .alu_op1_ra(de_alu_op1_ra),
		       .alu_op1_rb(de_alu_op1_rb),
		       .alu_op2_rb(de_alu_op2_rb),
		       .mem_load(de_mem_load),
		       .mem_store(de_mem_store),
		       .pc_plus_4(fd_pc_plus_4),
		       .pc_plus_4_out(de_pc_plus_4),
		       .instr_class(de_class),
		       .is_call(de_is_call),
		       .mem_width(de_mem_width),
		       .update_flags(de_update_flags),
		       .update_carry(de_update_carry),
                       .cr_sel(de_cr_sel),
                       .write_cr(de_write_cr),
                       .is_swi(de_is_swi),
		       .is_rfe(de_is_rfe),
		       .illegal_instr(df_illegal_instr),
		       .exception_start_in(fd_exception_start),
		       .exception_start_out(de_exception_start),
		       .i_fetched(fd_i_fetched),
		       .i_valid(de_i_valid),
		       .bkpt_hit(bkpt_hit));

oldland_exec	execute(.clk(clk),
			.rst(dbg_rst),
			.ra(de_ra),
			.rb(de_rb),
			.imm32(de_imm32),
			.pc_plus_4(de_pc_plus_4),
			.rd_sel(de_rd_sel),
			.update_rd(de_update_rd),
			.alu_opc(de_alu_opc),
			.branch_condition(de_branch_condition),
			.alu_op1_ra(de_alu_op1_ra),
			.alu_op1_rb(de_alu_op1_rb),
			.alu_op2_rb(de_alu_op2_rb),
			.mem_load(de_mem_load),
			.mem_store(de_mem_store),
			.mem_width(de_mem_width),
			.branch_taken(ef_branch_taken),
			.stall_clear(ef_stall_clear),
			.alu_out(em_alu_out),
			.mem_load_out(em_mem_load),
			.mem_store_out(em_mem_store),
			.mem_width_out(em_mem_width),
			.wr_val(em_wr_val),
			.wr_result(em_update_rd),
			.rd_sel_out(em_rd_sel),
			.instr_class(de_class),
			.is_call(de_is_call),
			.update_flags(de_update_flags),
			.update_carry(de_update_carry),
			.mar(em_mar),
			.mdr(em_mdr),
			.mem_wr_en(em_mem_wr_en),
                        .cr_sel(de_cr_sel),
                        .write_cr(de_write_cr),
                        .is_swi(de_is_swi),
			.is_rfe(de_is_rfe),
			.vector_base(e_vector_base),
			.pc_plus_4_out(em_pc_plus_4),
			.data_abort(m_data_abort),
			.exception_start(de_exception_start),
			.i_valid(de_i_valid),
			.i_valid_out(em_i_valid),
			.irqs_enabled(ei_irqs_enabled),
			.exception_disable_irqs(fe_disable_irqs),
			.dbg_cr_sel(dbg_cr_sel),
			.dbg_cr_val(dbg_cr_val),
			.dbg_cr_wr_val(dbg_cr_wr_val),
			.dbg_cr_wr_en(dbg_cr_wr_en),
			.irq_start(fe_irq_start),
			.irq_fault_address(fe_irq_fault_address),
			.cpuid_sel(cpuid_sel),
			.cpuid_val(cpuid_val));

oldland_memory	mem(.clk(clk),
		    .rst(dbg_rst),
		    .load(em_mem_load),
		    .store(em_mem_store),
		    .addr(em_mar),
		    .mdr(em_mdr),
		    .mem_wr_en(em_mem_wr_en),
		    .width(em_mem_width),
		    .wr_val(em_wr_val),
		    .update_rd(em_update_rd),
		    .rd_sel(em_rd_sel),
		    .reg_wr_val(mw_wr_val),
		    .update_rd_out(mw_update_rd),
		    .rd_sel_out(mw_rd_sel),
		    .d_addr(d_addr),
		    .d_bytesel(d_bytesel),
		    .d_wr_en(d_wr_en),
		    .d_wr_val(d_wr_val),
		    .d_data(d_data),
		    .d_access(d_access),
		    .d_ack(d_ack),
		    .d_error(d_error),
		    .complete(mf_complete),
		    .dbg_en(stopped),
		    .dbg_access(dbg_mem_access),
		    .dbg_wr_en(dbg_mem_wr_en),
		    .dbg_addr(dbg_mem_addr),
		    .dbg_width(dbg_mem_width),
		    .dbg_wr_val(dbg_mem_wr_val),
		    .dbg_rd_val(dbg_mem_rd_val),
		    .dbg_compl(dbg_mem_compl),
		    .data_abort(m_data_abort),
		    .i_valid(em_i_valid),
		    .busy(m_busy));

oldland_regfile	regfile(.clk(clk),
			.rst(dbg_rst),
			.ra_sel(d_ra_sel),
			.rb_sel(d_rb_sel),
			.rd_sel(mw_rd_sel),
			.wr_en(mw_update_rd),
			.wr_val(mw_wr_val),
			.ra(ra),
			.rb(rb),
			.dbg_reg_sel(dbg_reg_sel),
			.dbg_reg_val(dbg_reg_val),
			.dbg_reg_wr_val(dbg_reg_wr_val),
			.dbg_reg_wr_en(dbg_reg_wr_en),
			.dbg_en(stopped));

/*
 * Forwarding logic.  We need to forward results from the end of the execute
 * stage back to the input of the ALU.
 */
always @(posedge clk) begin
	e_ra_sel <= d_ra_sel;
	e_rb_sel <= d_rb_sel;
end

always @(*) begin
	if (em_rd_sel == e_ra_sel && em_update_rd)
		de_ra = em_alu_out;
	else if (mw_rd_sel == e_ra_sel && mw_update_rd)
		de_ra = mw_wr_val;
	else
		de_ra = ra;

	if (em_rd_sel == e_rb_sel && em_update_rd)
		de_rb = em_alu_out;
	else if (mw_rd_sel == e_rb_sel && mw_update_rd)
		de_rb = mw_wr_val;
	else
		de_rb = rb;
end

endmodule
