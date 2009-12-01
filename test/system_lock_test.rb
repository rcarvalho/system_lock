require 'test/unit'
require 'rubygems'
require 'memcache'
require "#{File.dirname(__FILE__)}/../init"

Internaut::SystemLock.memcached_instance = MemCache.new(["127.0.0.1:11211"])

class SystemLockTest < Test::Unit::TestCase
  
  def test_serialize_calls
    Internaut::CacheTest.clear # clear the old test results, if any
    puts "Spawning processes, please wait..."
    threads = []
    10.times do
      threads << Thread.new do
        system %{#{File.dirname(__FILE__)}/../../../../script/runner --environment=test "Internaut::SystemLock.critical_section('unique'){|| sleep(0.1) }" > /dev/null}
      end
    end

    puts "Waiting for all processes to execute"
    threads.each{|t| t.join}
    
    puts "Analyzing results.  Making sure each process is serialized correctly."
    results = Internaut::CacheTest.result.split(',')
    index = 0
    # making sure we have paired 'enter and exit' for each process
    while results.any? do
      index = 0 unless results[index+1]
      action,     process_id       = results[index].split(' ') 
      next_action, next_process_id = results[index+1].split(' ')
      if action == 'entering' && next_action == 'exiting' && process_id == next_process_id
        2.times{ results.delete_at index }
      else
        index += 1
      end
    end
    # if we made it here and aren't in an infinite loop we entered and exited all processes cleanly
    assert results.empty?
  end

end