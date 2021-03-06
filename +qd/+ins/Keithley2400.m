classdef Keithley2400 < qd.classes.ComInstrument
    % Currently this class only supports sourcing a voltage and reading currents.

    properties
        ramp_rate = []; % Ramp rate in V/s. Default is [] which disables ramping.
        ramp_step_size = 10E-3; % Step size to make when ramping. Default is 10 mV
        current_future;
        % The Keithley 2600 series can emulate a 2400. Set this to true if you
        % are using it in this way (this enables workarounds for minor bugs
        % this introduces).
        is_2600_in_disguise = false;
    end

    properties(Access=private)
        output_format_set = false;
        limit_low = -200;
        limit_high = 200;
    end

    methods
        function obj = Keithley2400(com)
            obj = obj@qd.classes.ComInstrument(com);
        end

        function r = model(obj)
            r = 'Keithley 2400 SourceMeter';
        end

        function r = channels(obj)
            r = {'curr', 'volt', 'resist'};
        end

        function reset(obj)
            obj.send('*rst');
            obj.set_output_format();
        end

        function set_limits(obj,low,high)
            % use .set_limits([],[]) to disable
            qd.util.assert((isnumeric(low) && isscalar(low)) || isempty(low))
            qd.util.assert((isnumeric(high) && isscalar(high)) || isempty(high))
            obj.limit_low = low;
            obj.limit_high = high;
        end

        function limits = get_limits(obj)
            limits = [obj.limit_low, obj.limit_high];
        end

        function set_output_format(obj)
            obj.send(':FORM:ELEM VOLT,CURR');
            obj.output_format_set = true;
        end

        function set_curr_compliance(obj, level)
            obj.sendf(':CURR:PROT %.16E', level);
        end

        function set_ramp_rate(obj, rate)
            qd.util.assert((isnumeric(rate) && isscalar(rate)) || isempty(rate))
            if rate==0
                obj.ramp_rate = [];
            else
                obj.ramp_rate = abs(rate);
            end
        end

        function set_ramp_step_size(obj, ramp_step_size)
            obj.ramp_step_size = ramp_step_size;
        end

        function turn_on_output(obj)
            obj.send(':OUTP:STAT 1')
        end

        function turn_off_output(obj)
            obj.send(':OUTP:STAT 0');
        end

        function set_NPLC(obj, nplc)
            obj.send([':SENS:VOLT:NPLC ', num2str(nplc)])
        end

        % function future = setc_async(obj, channel, value)
        % % set async does not work perfectly:
        % % - the end_value is first set on exec()
        % % - maybe a solution is to always compute 2500 pts also on small sweeps?
        % % - no abort exists
        % % - when number of points is too large the step size will be reduced to have the full sweep within
        % %   the 2500 points.
        %     function exec()
        %         % This is just a dummy exec function
        %     end
        %     switch channel
        %         case 'volt'
        %             future = [];
        %             if value<obj.limit_low
        %                 warning('Out of limit!\nSetting value to min: %sV',num2str(obj.limit_low));
        %                 value = obj.limit_low;
        %             elseif value>obj.limit_high
        %                 warning('Out of limit!\nSetting value to max: %sV',num2str(obj.limit_high));
        %                 value = obj.limit_high;
        %             end
        %             if ~isempty(obj.ramp_rate)
        %                 future = obj.set_volt_with_ramp_async(value);
        %             else
        %                 obj.sendf('SOUR:VOLT %.16E', value);
        %                 future = qd.classes.SetFuture(@exec);
        %             end
        %         case 'curr'
        %             obj.sendf('SOUR:CURR %.16E', value)
        %             future = qd.classes.SetFuture(@exec);
        %         otherwise
        %             error('not supported.')
        %     end
        %     obj.current_future = future;
        % end

        function setc(obj, channel, value)
            switch channel
                case 'volt'
                    if value<obj.limit_low
                        warning('Out of limit!\nSetting value to min: %sV',num2str(obj.limit_low));
                        value = obj.limit_low;
                    elseif value>obj.limit_high
                        warning('Out of limit!\nSetting value to max: %sV',num2str(obj.limit_high));
                        value = obj.limit_high;
                    end
                    if ~isempty(obj.ramp_rate)
                        obj.set_volt_with_ramp(value)
                    else
                        obj.sendf('SOUR:VOLT %.16E', value)
                    end
                case 'curr'
                    obj.sendf('SOUR:CURR %.16E', value)
                otherwise
                    error('not supported.')
            end
        end

        function val = getc(obj, channel)
            % This is not fool-proof, since it does not
            % detect if changes are made.
            if ~obj.output_format_set
                obj.set_output_format();
            end
            switch channel
                case 'curr'
                    res = obj.querym(':READ?', '%g, %g');
                    val = res(2);
                case 'volt'
                    res = obj.querym(':READ?', '%g, %g');
                    val = res(1);
                case 'resist'
                    res = obj.querym(':READ?', '%g, %g');
                    val = res(1) / res(2);
                otherwise
                    error('not supported.')
            end
        end

        function fix_errors(obj)
            % used to fix not responding Keithley after aborting a
            % sweep with CTRL+C only wors sometimes
            obj.send('SOUR:VOLT:MODE FIX')
            obj.send('TRIG:COUN 1')
            obj.send('TRIG:DEL 0');
            obj.send('SENS:FUNC:ON "CURR"');
        end


        function stop_autorange(obj)
            obj.send('SOUR:VOLT:RANG 210')
            obj.send('SOUR:VOLT:AUTO 0')
        end

        function r = describe(obj, register)
            r = obj.describe@qd.classes.ComInstrument(register);
            r.config = struct();
            r.is_2600_in_disguise = obj.is_2600_in_disguise;
            queries = { ...
                'FORM:ELEM', 'OUTP:STAT', 'OUTP:SMOD', 'ROUT:TERM', 'FUNC:CONC', ...
                'FUNC:ON', 'CURR:RANG:UPP', 'CURR:RANG:AUTO', 'CURR:NPLC', 'CURR:PROT', ...
                'VOLT:RANG:UPP', 'VOLT:RANG:AUTO', 'VOLT:NPLC', 'VOLT:PROT', 'RES:RANG:UPP', ...
                'RES:RANG:AUTO', 'RES:NPLC', 'AVER:STAT', 'AVER:COUN', 'AVER:TCON', ...
                'SOUR:DEL', 'SOUR:FUNC', 'SOUR:CURR:LEV', 'SOUR:CURR:RANG', ...
                'SOUR:VOLT:LEV', 'SOUR:VOLT:RANG'};
            if not(obj.is_2600_in_disguise)
                % This query hangs for a 2600 running with the 2400 persona.
                queries{end + 1} = 'SOUR:VOLT:PROT';
            end
            for q = queries
                question = [':' q{1} '?'];
                simplified = lower(strrep(q{1}, ':', '_'));
                r.config.(simplified) = obj.query(question);
            end
        end
    end

    methods(Access=private)
        function set_volt_with_ramp(obj, val)
            current_value = obj.getc('volt');
            obj.send('SENS:FUNC:OFF:ALL');
            obj.send('SOUR:VOLT:MODE SWE');
            obj.sendf('TRIG:DEL %.16E', obj.ramp_step_size/obj.ramp_rate);
            while true
                step = obj.ramp_step_size * sign(val - current_value);
                first_value = current_value + step;
                number_of_points =  floor(abs(val - first_value) / obj.ramp_step_size);
                number_of_points = min(2500, number_of_points); % this limit is set by the instrument
                if number_of_points <= 1
                    break
                end
                end_value = current_value + step*number_of_points;
                if val > current_value
                    end_value = min(end_value, val);
                else
                    end_value = max(end_value, val);
                end
                % The keithley calculates all point in the sweep in advance
                % whenever parameters are changed, therefore setting the sweep
                % to two points while setting start and stop greatly speeds up
                % the process.
                obj.send('SOUR:SWE:POIN 2');
                obj.sendf('SOUR:VOLT:START %.16E', first_value);
                obj.sendf('SOUR:VOLT:STOP %.16E', end_value);
                obj.sendf('SOUR:SWE:POIN %d', number_of_points);
                obj.sendf('TRIG:COUN %d', number_of_points);
                obj.send('INIT');
                current_value = end_value;
            end
            obj.send('*OPC?');
            while true
                status = fscanf(obj.com, '%d');
                if ~isempty(status) && status == 1
                    break;
                end
            end
            obj.send('SOUR:VOLT:MODE FIX')
            obj.send('TRIG:COUN 1')
            obj.sendf('TRIG:DEL %.16E', round(abs(current_value - val)/obj.ramp_rate*10000)/10000);
            obj.sendf('SOUR:VOLT %.16E', val);
            obj.send('TRIG:DEL 0');
            obj.send('SENS:FUNC:ON "CURR"');
        end

        function future = set_volt_with_ramp_async(obj, val)
            current_value = obj.getc('volt');
            obj.send('SENS:FUNC:OFF:ALL');
            obj.send('SOUR:VOLT:MODE SWE');
            obj.sendf('TRIG:DEL %.16E', obj.ramp_step_size/obj.ramp_rate);

            step = obj.ramp_step_size * sign(val - current_value);
            first_value = current_value + step;
            number_of_points =  floor(abs(val - first_value) / obj.ramp_step_size);

            if number_of_points > 2500
                warning(['Number of points exceeded hardware-limit and will be set to maximum (2500): ',num2str(number_of_points)])
                number_of_points = 2500
                new_ramp_step_size =  ceil(abs(val - first_value) / number_of_points);
                obj.sendf('TRIG:DEL %.16E', new_ramp_step_size/obj.ramp_rate);
                step = new_ramp_step_size * sign(val - current_value)
            end
            end_value = current_value + step*number_of_points;
            number_of_points = min(2500, number_of_points); % this limit is set by the instrument

            if val > current_value
                end_value = min(end_value, val);
            else
                end_value = max(end_value, val);
            end
            % The keithley calculates all point in the sweep in advance
            % whenever parameters are changed, therefore setting the sweep
            % to two points while setting start and stop greatly speeds up
            % the process.
            obj.send('SOUR:SWE:POIN 2');
            obj.sendf('SOUR:VOLT:START %.16E', first_value);
            obj.sendf('SOUR:VOLT:STOP %.16E', end_value);
            obj.sendf('SOUR:SWE:POIN %d', number_of_points);
            obj.sendf('TRIG:COUN %d', number_of_points);
            obj.send('INIT');


            function exec()
                current_value = end_value;
                obj.send('*OPC?');
                while true
                    status = fscanf(obj.com, '%d');
                    if ~isempty(status) && status == 1
                        break;
                    end
                end
                obj.send('SOUR:VOLT:MODE FIX')
                obj.send('TRIG:COUN 1')
                obj.sendf('TRIG:DEL %.16E', round(abs(current_value - val)/obj.ramp_rate*10000)/10000);
                obj.sendf('SOUR:VOLT %.16E', val);
                obj.send('TRIG:DEL 0');
                obj.send('SENS:FUNC:ON "CURR"');
            end
            future = qd.classes.SetFuture(@exec);
        end
    end
end
