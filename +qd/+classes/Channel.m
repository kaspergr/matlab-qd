classdef Channel < qd.classes.Nameable
    properties
        instrument
        channel_id
        meta = struct()
    end
    methods
        function r = default_name(obj)
            if ~isempty(obj.instrument)
                r = [obj.instrument.name '/' obj.channel_id];
            else
                r = ['special/' obj.channel_id];
            end
        end

        function r = describe(obj, register)
            r = struct();
            r.name = obj.name;
            r.default_name = obj.default_name;
            r.channel_id = obj.channel_id;
            r.meta = obj.meta;
            if ~isempty(obj.instrument)
                r.instrument = register.put('instruments', obj.instrument);
            end
        end

        function val = get(obj)
            if ~isempty(obj.instrument)
                val = obj.instrument.getc(obj.channel_id);
            else
                error('Not supported');
            end
        end

        function set(obj, val)
            if ~isempty(obj.instrument)
                obj.instrument.setc(obj.channel_id, val);
            else
                error('Not supported');
            end
        end

        function obj = set_meta(obj, meta)
            obj.meta = meta;
        end
    end
end