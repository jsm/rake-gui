require 'pathname'
require 'strscan'
require 'yaml'

def running_time
  (Time.mktime(0)+(Time.now-settings.start_time)).strftime("%H:%M:%S")
end

def get_style(status, seconds_since_modified)
  case status
  when :successful then
    'background-color: #5cb85c'
  when :failed then
    'background-color: #d9534f'
  when :running then
    alpha = [seconds_since_modified, 5].min/5
    "background-color: rgba(240, 173, 78, #{alpha})"
  end
end

def get_task_status(metadata)
  case metadata['status']
  when 'successful' then
    :successful
  when 'failed' then
    :failed
  else
    :running
  end
end

def get_subtasks(directory)
  children = directory.children.select { |c| c.directory? }
  current_time = Time.now

  children.map do |c|
    metadata_file = File.join(c, 'metadata')
    if File.exist?(metadata_file)
      metadata = YAML::load_file(metadata_file)
    else
      metadata = {}
    end

    status = get_task_status(metadata)
    seconds_since_modified = current_time - File.mtime(File.join(c, 'main.log'))

    {
      name: c.basename.to_s,
      url: '/console/' + c.relative_path_from(settings.working_directory).to_s,
      seconds_since_modified: seconds_since_modified,
      style: get_style(status, seconds_since_modified),
    }
  end.sort_by{|c| -c[:seconds_since_modified]}
end

def get_executor_status(metadata, id)
  case metadata[id]
  when 'successful' then
    :successful
  when 'failed' then
    :failed
  else
    :running
  end
end

def get_executors(directory)
  output = {
    successful: [],
    failed: [],
    running: [],
  }

  return output unless directory.exist?

  executors = directory.children.select { |c| c.extname == '.log' && c.basename.to_s != 'main.log' }

  metadata_file = File.join(directory, 'executors.metadata')
  if File.exist?(metadata_file)
    metadata = YAML::load_file(metadata_file)
  else
    metadata = {}
  end

  current_time = Time.now

  executors.each do |c|
    id = c.basename('.log').to_s
    status = get_executor_status(metadata, id)
    seconds_since_modified = current_time - File.mtime(c)
    info = {
      name: id,
      url: '/console/' + c.dirname.relative_path_from(settings.working_directory).to_s + '?executor=' + id,
      style: get_style(status, seconds_since_modified),
    }
    output[status] << info
  end

  return output
end

def ansi_to_html(data)
  data = data.dup

  { 1 => :nothing,
    2 => :nothing,
    4 => :nothing,
    5 => :nothing,
    7 => :nothing,
    30 => :black,
    31 => :red,
    32 => :green,
    33 => :yellow,
    34 => :blue,
    35 => :magenta,
    36 => :cyan,
    37 => :white,
    40 => :nothing,
    41 => :nothing,
    43 => :nothing,
    44 => :nothing,
    45 => :nothing,
    46 => :nothing,
    47 => :nothing,
  }.each do |key, value|
    if value != :nothing
      data.gsub!(/\e\[0;#{key};49m/,"<span style=\"color:#{value}\">")
    else
      data.gsub!(/\e\[0;#{key};49m/,"<span>")
    end
  end
  data.gsub!(/\e\[0m/,'</span>')
  return data
end
