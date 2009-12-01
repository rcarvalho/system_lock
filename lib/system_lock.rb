# timeout must be longer than it takes to execute code block
module Internaut
  class CacheTest
    @@path = 'SystemLock::internaut_test_values'
    def self.add(value)
      if val = result
        value = "#{val},#{value}"
      end
      SystemLock.memcached_instance.set @@path, value, 60.seconds.to_i
    end

    def self.result
      SystemLock.memcached_instance.get(@@path)
    end
    
    def self.clear
      SystemLock.memcached_instance.set @@path, nil
    end
  end

  class SystemLock
    @@enabled = true

    def self.disable!
      @@enabled = false
    end

    def self.enable!
      @@enabled = true
    end

    def self.enabled?
      @@enabled
    end
    
    def self.memcached_instance= cache
      @@CACHE = cache
    end
    
    def self.memcached_instance
      @@CACHE
    end

    def self.critical_section(unique_code_block_identifier, timeout=60)
      # puts "entering cc #{Process.pid}"
      yield and return unless @@enabled

      begin
        path = "SystemLock::#{unique_code_block_identifier}"
        # puts "waiting for lock..."
        # wait until the lock is released or until we timeout

        # We use a combination of the process id and a unique app id in case the process id is the same on two different machines
        unique_process_id = UNIQUE_APPLICATION_INSTANCE_ID + Process.pid.to_s
        got_the_lock = false
        while( !got_the_lock )
          while( (cache = @@CACHE.get(path)) && (cache[0] != unique_process_id) rescue return ) do
            # puts "locked waiting.... #{path}: #{Process.pid} : #{cache.inspect}"
            sleep(0.1)
          end
          
          counter = cache && cache[1]
          counter ||= 0
          # set the lock
          set_lock_to = [unique_process_id,counter]
          # puts "attempting to grab lock: #{set_lock_to.inspect}"
          @@CACHE.set( path, set_lock_to, timeout.seconds.to_i )
          if @@CACHE.get(path)[0] == unique_process_id
            # we have to double check to make sure we actually got the lock
            # sleep(0.1)
            cache = @@CACHE.get(path)
            if cache[0] == unique_process_id
              # puts "got the lock"
              got_the_lock = true
              
              # puts "grabbing lock: #{set_lock_to.inspect}"
              # add reference - we use ref counting for recursive calls
              set_lock_to = [unique_process_id,cache[1]+1]
              @@CACHE.set( path, set_lock_to, timeout.seconds.to_i ) 
            else
              redo
            end
          else
            # puts "redoing: #{RefCounter.get(path)}, #{unique_process_id}"
            redo
          end
        end
        # puts "acquired lock #{Process.pid}"
        CacheTest.add "entering #{Process.pid}" if Rails.env.test?

        # Do the action
        yield

        CacheTest.add "exiting #{Process.pid}" if Rails.env.test?
        # puts "leaving lock #{Process.pid}"
      # make sure we always unlock, even if there is an exception
      ensure
        cache = @@CACHE.get(path)
        if cache
          if cache[1] > 1
            
            cache[1] -= 1
            # puts "decrementing count to #{cache.inspect}"
            @@CACHE.set( path, cache)
          else
            @@CACHE.set( path, nil)
            # puts "decrementing count to nil - #{path}"
          end
        end
      end
    end
  end
  
end