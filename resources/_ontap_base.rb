# Import REST DSL
use 'core::rest_resource'

# Add target API specific methods and helpers
action_class do
  # Handle data transformation, paging and asynchronous execution
  def rest_postprocess(response)
    data = response.data

    # Search responses come back as Array
    data = data.key?('records') ? data.fetch('records') : data

    # Paging
    if data.is_a?(Hash) && data.dig('_links', 'next')
      raise NotImplementedError, 'Received paged response, but paging not yet implemented'
    end

    # Wait for asynchronous operations
    if data.is_a?(Hash) && data.key?('job')
      job_uuid = data.dig('job', 'uuid')
      wait_for_job(job_uuid)
    end

    if data.is_a?(Hash) && data.key?('records')
      response.data = data.fetch('records')
    else
      response.data = data
    end

    response
  end

  # Transform responses into readable error messages
  def rest_errorhandler(error_obj)
    raise error_obj unless error_obj.is_a? RestClient::Exception

    error_message = case error_obj
                    when RestClient::NotFound
                      url = error_obj.response.net_http_res.uri
                      "Path not found: #{url}"
                    else
                      error = JSON.parse(error_obj.http_body)
                      format('%<message>s: %<target>s',
                        message: error.dig('error', 'message'),
                        target: error.dig('error', 'target'))
                end

    raise ::Chef::Exceptions::RestTargetError, "ONTAP: #{error_message}"
  end

  private

  READABLE_UNITS = %w[by KB MB GB TB PB].freeze

  def from_ontap_readable_size(string)
    unit   = string.to_s[-2..]
    factor = 1024**(READABLE_UNITS.index(unit) || 0)

    string.to_i * factor
  end

  # For asynchronous execution (HTTP Code 202), wait for completion of the job
  def wait_for_job(uuid, interval: 5, timeout: 60)
    logger.debug format('ONTAP: Job %<uuid>s wait for completion', uuid: uuid)

    Timeout.timeout(timeout) do
      loop do
        raw = api_connection.get "/api/cluster/jobs/#{uuid}"
        status = rest_postprocess(raw).data

        # REST model: https://library.netapp.com/ecmdocs/ECMLP2876964/html/index.html#model-job
        case status['state']
        when 'success'
          duration = Time.parse(status['end_time']) - Time.parse(status['start_time'])

          logger.trace format('ONTAP: Job %<uuid>s successful (Runtime: %<duration>.1fs)',
                              uuid: uuid,
                              duration: duration)
          return
        when 'failure'
          error_message = format('ONTAP: Job %<uuid>s failed: %<message>s',
                                  uuid: uuid,
                                  message: status['message'])

          raise ::Chef::Exceptions::RestOperationFailed, error_message
        end

        sleep interval
      end
    end
  rescue Timeout::Error => _e
    raise ::Chef::Exceptions::RestTimeout, "ONTAP: Job #{uuid} timeout exceeded"
  end
end
