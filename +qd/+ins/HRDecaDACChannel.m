classdef HRDecaDACChannel < qd.classes.Channel
    % This is far from optimal, many ways to break this.
    % TODO: Make fine channel ramp as well...
    properties(Access=private)
        num
        mode
        board
        chan
        range_low
        range_high
        ramp_rate % volts per second
        limit_low
        limit_high
        wait_for_ramp = true
        slope
        offset
        
    end
    methods
        function obj = HRDecaDACChannel(num,mode)
            persistent warning_issued;
            obj.num = num;
            obj.board = floor(obj.num/4);
            obj.chan = mod(obj.num, 4);
            obj.mode = mode;
            obj.range_low = -10.0;
            obj.range_high = 10.0;
            obj.ramp_rate = 0.1;
            obj.slope = 1;
            obj.offset = 0;
            if isempty(warning_issued)
                warning(['DecaDAC drivers: ' ...
                    'No handling of DecaDAC range yet, setting -10V to 10V. '])
                warning_issued = true;
            end
        end

        function set_limits(obj, low, high)
            qd.util.assert((isnumeric(low) && isscalar(low)) || isempty(low))
            qd.util.assert((isnumeric(high) && isscalar(high)) || isempty(high))
            obj.limit_low = low;
            obj.limit_high = high;
        end
        
        function set_slope(obj, slope)
            qd.util.assert((isnumeric(slope) && isscalar(slope)) || isempty(slope))
            obj.slope = slope;
        end
        
        function set_offset(obj, offset)
            qd.util.assert((isnumeric(offset) && isscalar(offset)) || isempty(offset))
            obj.offset = offset;
        end

        function range = get_limits(obj)
            range = [obj.limit_low, obj.limit_high];
        end
        
        function set(obj,val)
            % Modes 0:off, 1:fine  2:coarse.
            if obj.mode == 0
                error('This Board is diabled.');
            elseif obj.mode == 1
                if obj.chan == 2 || obj.chan == 3
                    error('I am the fine channel, leave me alone!')
                end
            elseif obj.mode == 2
                
            else
                error('No valid mode')
            end
            % Shorthand for obj.instrument
            ins = obj.instrument;
            % Validate the input for common errors.
            qd.util.assert(isnumeric(val));
            val = (val/obj.slope)-obj.offset;
            
            if (val > obj.range_high) || (val < obj.range_low)
                error('%f is out of range. Remember slope and offset.', val);
            end
            % FQHE 2DEG can not handle positive gates voltages.
            if ~isempty(obj.limit_low) && ((val < obj.limit_low) || (val > obj.limit_high))
                error('Value must be within %f and %f . Remember slope and offset.', obj.limit_low, obj.limit_high);
            end
            
            [bin,c_bin,f_bin] = obj.get_bins(val);

            if isempty(obj.ramp_rate)
                if obj.mode == 1
                    % write in one step
                    ins.queryf('B%d;C%d;D%d;B%d;C%d;D%d;',obj.board, obj.chan, c_bin, obj.board, obj.chan+2, f_bin);
                else
                    % send coarse bin only, and use the the 16bit value.
                    ins.queryf('B%d;C%d;D%d;',obj.board, obj.chan, bin);
                end
            else % The else part is a ramping set.
                % Merlin: I dont know how to do this for both channels, so
                % I just ramp roughly with the coarse channel, in the end I
                % send the exact value to both.
                %
                % Get the current coarse value.
                obj.select();
                current = ins.querym('d;', 'd%d!');
                if obj.wait_for_ramp == false && obj.mode == 1
                    % if ramping blind, set fine channel first.
                    bin = c_bin;
                    ins.queryf('B%d;C%d;D%d;', obj.board, obj.chan+2, f_bin);
                end
                obj.select();
                % set the limit for the ramp
                if current < bin
                    ins.queryf('U%d;', bin);
                elseif current > bin
                    ins.queryf('L%d;', bin);
                else
                    % Nothing to do, fine channel will just be set.
                end
                % We set the ramp clock period to 1000 us. Changing the clock
                % is not supported for all DACs it seems, for those that do
                % not support it, I hope the default is always 1000.
                ramp_clock = 1000;
                % Calculate the required slope (see the DecaDAC docs)
                r_slope = ceil((obj.ramp_rate / obj.range_span() * ramp_clock * 1E-6) * (2^32));
                r_slope = r_slope * sign(bin - current);
                
                % Initiate the ramp.
                ins.queryf('T%d;G0;S%d;', ramp_clock, r_slope);
                % Now we wait until the goal has been reached (maybe)
                if obj.wait_for_ramp == true
                    while true
                        val = ins.querym('d;', 'd%d!');
                        if val == bin
                            break;
                        end
                        pause(ramp_clock * 1E-6 * 3); % wait a few ramp_clock periods
                        % TODO, if this is taking too long. Abort the ramp with an error.
                    end
                    if obj.mode == 1
                        % If fine Channel is activated, send the exact value now.
                        ins.queryf('B%d;C%d;D%d;B%d;C%d;D%d;',obj.board, obj.chan, c_bin, obj.board, obj.chan+2, f_bin);
                    end
                    % Set back everything
                    obj.select();
                    ins.queryf('S0;L0;U%d;', 2^16-1);
                end
            end
        end
        
        function [bin,c_bin,f_bin] = get_bins(obj, val)
            % Following the comments on WIKI about DAC:
            % The coarse channel is used as little as possible. Thus
            % limited to ~8 bit, when exactly 8 bit are used the fine
            % channel does not span over the remaining steps, so the coarse
            % range (c_BinRange)is increased by 1.
            
            BinRange = 2^16 - 1;
            c_BinRange = 2^8;
            
            nval = val - obj.range_low;
            frac = nval/obj.range_span();
            
            bin = round(frac*BinRange);
            c_bin = floor(frac*c_BinRange)*c_BinRange-1;
            
            f_nval = (nval - ( c_bin * obj.range_span() / BinRange ) );
            f_frac = f_nval/0.1;  % hard-coded range of 100mV
            f_bin = round(f_frac*BinRange);
            
            if f_bin>65535
                warning('f_bin too high: %d - This indicates a bug!',c_bin);
                f_bin = 65535;
            end
            if f_bin<0
                warning('f_bin too low: %d - This indicates a bug!',f_bin);
                f_bin = 0;
            end
        end
        
        
        function cc(obj, val)
            ins = obj.instrument;
%             obj.select();
            ins.query(val)
        end
        
        function set_setpoint(obj, val)
            % Same as obj.set but without wait time (added by Guen on 12/10/2013)
            % Use the same code but skip waiting.
            obj.wait_for_ramp = false;
            obj.set(val)
            obj.wait_for_ramp = true;
        end

        function val = get(obj)
            obj.select();
            raw = obj.instrument.querym('d;', 'd%d!');
            val = raw / 2^16 * obj.range_span() + obj.range_low;
        end

        function set_ramp_rate(obj, rate)
            % Set the ramping rate of this channel instance. Set this to [] to disable ramping.
            % Rate is in volts per second.
            qd.util.assert((isnumeric(rate) && isscalar(rate)) || isempty(rate))
            if rate==0.0
                obj.ramp_rate = [];
            else
                obj.ramp_rate = abs(rate);
            end
        end
        
        function rate = get_ramp_rate(obj)
            rate = obj.ramp_rate;
        end

        function r = describe(obj, register)
            r = obj.describe@qd.classes.Channel(register);
            r.ramp_rate = obj.ramp_rate;
            r.current_value = obj.get();
        end
    end
    methods(Access=private)
        function select(obj)
            % Select this channel on the DAC.
            obj.instrument.queryf('B%d;C%d;', floor(obj.num/4), mod(obj.num, 4));
        end
        
        function select_fine(obj)
            % Select the corresponding fine channel on the DAC.
            obj.instrument.queryf('B%d;C%d;', floor(obj.num/4), mod(obj.num, 4)+2);
        end

        function span = range_span(obj)
            span = obj.range_high - obj.range_low;
        end
    end
end