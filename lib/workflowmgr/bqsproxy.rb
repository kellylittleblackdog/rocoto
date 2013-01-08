##########################################
#
# module WorkflowMgr
#
##########################################
module WorkflowMgr

  ##########################################
  #
  # Class BQSProxy
  #
  ##########################################
  class BQSProxy

    require 'workflowmgr/utilities'
    require 'workflowmgr/bqs'
    require 'system_timer'
    require 'drb'
    require 'workflowmgr/workflowoption'
    require 'workflowmgr/workflowconfig'

    ##########################################
    #
    # initialize
    #
    ##########################################
    def initialize(batchSystem,config,options)

      # Store the batch system proxy creation parameters
      @batchSystem=batchSystem
      @config=config
      @options=options

      # Initialize the batch system server
      initbqs

      # Define the stop! method to increase performance by avoiding calls to method_missing
      (class << self; self; end).instance_eval do
        define_method :stop! do |*args|
          begin
            SystemTimer.timeout(30) do
              @bqServer.send(:stop!,*args)
            end
          rescue DRb::DRbConnError
            msg="WARNING! Can't shut down batch queue server because it is not running."
            WorkflowMgr.stderr(msg,1)
            WorkflowMgr.log(msg)
          rescue Timeout::Error
            msg="WARNING! Can't shut down batch queue server process because it is unresponsive and is probably wedged."
            WorkflowMgr.stderr(msg,1)
            WorkflowMgr.log(msg)
          end
        end
      end

      # Define methods to increase performance by avoiding calls to method_missing
      (WorkflowMgr::const_get("BQS").instance_methods-Object.instance_methods+[:__drburi]).each do |m|
        (class << self; self; end).instance_eval do
          define_method m do |*args|
            retries=0
            begin
              SystemTimer.timeout(60) do
                @bqServer.send(m,*args)
              end
            rescue DRb::DRbConnError
              if retries < 1
                retries+=1
                msg="WARNING! WorkflowBQS server process died.  Attempting to restart and try again."
                WorkflowMgr.stderr(msg,1)
                WorkflowMgr.log(msg)
                initbqs
                retry
              else
                msg="ERROR! WorkflowBQS server process died.  #{retries} attempts to restart the server have failed, giving up."
                WorkflowMgr.log(msg)
                raise msg
              end
            rescue Timeout::Error
              msg="ERROR! WorkflowBQS server process is unresponsive and is probably wedged."
              WorkflowMgr.log(msg)
              raise msg
            end

          end
        end
      end

    end

  private

    ##########################################
    #
    # initbqs
    #
    ##########################################
    def initbqs

      # Get the WFM install directory
      wfmdir=File.dirname(File.dirname(File.expand_path(File.dirname(__FILE__))))

      # Create the batch queue system object
      begin

	# Initialize the 
        bqs=BQS.new(@batchSystem,@options.database,@config)

	if @config.BatchQueueServer

          # Ignore SIGINT while launching server process
          Signal.trap("INT",nil)

          # Launch server process
          @bqServer,@bqHost,@bqPID=WorkflowMgr.launchServer("#{wfmdir}/sbin/rocotobqserver")
          @bqServer.setup(bqs,@options.verbose)

          # Restore default SIGINT handler
          Signal.trap("INT","DEFAULT")

	else
          @bqServer=bqs
        end

      rescue

        # Try to stop the bqserver if something went wrong
	if @config.BatchQueueServer
          @bqServer.stop! unless @bqServer.nil?
        end

        # Raise fatal exception
        msg="ERROR: Could not launch batch queue server process. #{$!}"
        WorkflowMgr.log(msg)
        raise msg

      end

    end

  end  # Class BQSProxy

end  # Module WorkflowMgr
