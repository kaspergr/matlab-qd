# *matlab-qd* tutorial

## Using instrument drivers.

While *matlab-qd* is a complete framework, you do not have to opt-in to
everything if you just want to use a single instrument driver from the
project. Let us try using a *Keithley 2600*. Make sure its turned on and
outputting a voltage.

```matlab
>> keithley = qd.ins.Keithley2600(gpib('ni', 0, 1));
```

The above code creates an instance of the Keithley2600 class. The `gpib` class
is from the MATLAB standard library.

Instruments have channels, you can query which by typing

```matlab
>> keithley.channels()
TODO, put output here.
```

You can get and set channels using the commands `getc` and `setc`.

```matlab
>> keithley.setc('v', 1.0); % The unit is volts.
TODO, put output here.
>> keithley.getc('i')
TODO, put output here.
```

Not all channels support both setting and geting, for instance

```matlab
>> keithley.setc('r', 1000);
TODO, put output here.
```

Furthermore, you should not expect `getc` to return the exact same value as is
set by `setc`. For instance, if a keithley is in current compliance, it will
limit the voltage, making the value returned by `keithley.getc('v')` lower
than what was set.

For further reference type `doc qd.classes.Instrument` in MATLAB.

### Configuring instruments

To configure an instrument, use methods on its instance. For instance

```matlab
>> keithley.turn_off_output();
>> keithley.set_compliance('i', 10E-9);
```

Only common configuration options are usually exposed. If you need something
that is not there, you can either add it to the drivers (see below), or bypass
it be talking to the instrument directly.

```matlab
>> keithley.query('print(smua.measure.analogfilter)');
```

For further reference see `doc qd.classes.ComInstrument`.

### Using channel objects

In addition to `setc` and `getc`, you can set and get a channel by first
instantiating a channel object

```matlab
>> voltage = keithley.channel('v');
>> current = keithley.channel('i');
>> voltage.set(3.0);
>> current.get()
TODO, put output here.
```

This lets you write code that works on individual channels, without worrying
about where these channels came from. A technique that is used extensively in
*matlab-qd*. All channels inherit from `qd.classes.Channel`.

### Ramping a channel (working with futures)

Many instruments support (or enforce) slowly ramping their outputs. Let us try
this out. For the keithley 2600, here is how you set the ramp rate.

```matlab
>> keithley.setc('v', 0);
>> keithley.turn_on_output();
>> keithley.ramp_rate.v = 0.5; % Set the ramp rate to 0.5 volts per second
>> tic; keithley.setc('v', 3); toc;
TODO, put output here.
```

Notice that `setc` *blocks* until the ramp is complete. If this is not
desirable, you can use `setc_async` (or `set_async` on a channel object).

```matlab
>> keithley.setc_async('v', 0); % This function returns imediately.
```

Notice, that if you call `setc` or `setc_async` again before the ramp is
complete, the ramp is aborted, a warning is printed, and a new ramp is
started. You can also call `keithley.current_future.abort()` to abort any
running ramp.

If you left out the semicolon, you may have noticed that `setc_async` returns
a `qd.classes.SetFuture` object. This can be used to wait until the ramp is
complete or to abort an ongoing ramp.

```matlab
>> future = keithley.setc_async('v', 3);
>> future.exec(); % wait until the ramp is complete.
>> future = keithley.setc_async('v', 0); % start a new ramp.
>> pause(2.0);
>> future.abort(); % abort it prematurely.
```

The real strength of futures comes when you need to ramp several channels. For
instance, if you have six gates driven by DecaDACs that need to be ramped 1
volt at 0.1 volt/second, ramping one at a time with `setc` would take 1 min.
However, this piece of code

```matlab
% First we initate all the ramping.
futures = {};
for i = 1:length(gates)
    futures{i} = gates{i}.set_async(1.0);
end
% Then we wait for the ramps to finish
for i = 1:length(gates)
    futures{i}.exec();
end
```

would only take 10 seconds. This method is used throughout *matlab-qd*. Note,
there is also a `get_async` for instrument with long integration times.

## Running measurements

Beyond being a collection of drivers with a uniform interface, *matlab-qd*
also offers classes that will let you run basic measurements with ease. First
we will look at two simple classes that we will use later.

The class `qd.data.Store` exist to create empty directorties in some base
folder into which data can be stored.

```matlab
>> store = qd.data.Store('D:\Data\Me\');
>> store.cd('DeviceNr1959');
>> blank_dir = store.new_dir()
```

The class `qd.Setup` is a class that knows every instrument in your setup.

```matlab
>> keithley.name = 'keithley';
>> decadac = qd.ins.DecaDAC2('COM1');
>> decadac.name = 'dac';
>> setup = qd.Setup();
>> setup.add_instrument(keithley);
>> setup.add_instrument(decadac);
```

There is also an `add_channel`.

The setup lets you lookup channels by name (preceded by the instrument name
and a `/`). For instance

```matlab
>> voltage = setup.find_channel('keithley/v');
>> voltage.set(0);
>> % or you can do
>> setup.setc('keithley/v', 0);
>> setup.setc('dac/CH0', 0);
```

and you can access instruements and named channels through the `ins` and
`chans` properties

```matlab
>> setup.ins.keithley.turn_output_on();
```

It is standard practice, to make a function in a `.m` file that sets up a
setup object for your setup.

### The *StadardRun* class

Lets try to run an experiment. Here is a simple IV curve.

```matlab
>> run = qd.run.StandardRun();
>> run.store = store;
>> run.setup = setup;
>> run.sweep('keithley/v', 0, 10, 100); % 0 to 10 in 100 steps.
>> run.input('keithley/i');
>> run.name = 'IV curve';
>> run.run();
```

The *sweep* and *input* methods look up a channels using the *setup*
configured for the run, but you could also pass a channel directly
(`run.sweep(voltage, 0, 10, 100);` and `run.input(current);`).

If you supply multiple sweeps, they are nested:

```matlab
>> gate = setup.find_channel('dac/CH0');
>> run.clear_sweeps();
>> run.sweep(gate, 0, 10, 11);
>> run.sweep('keithley/v', 0, 10, 100);
>> run.name = 'Gate dependence';
>> run.run(); % One IV curve for each gate value.
```

Note, many of the methods of a *run* return the *run* itself so that calls can
be chained. E.g.

```matlab
>> run.clear_sweeps().sweep('keithley/v', 0, 10, 100).set_name('IV curve 2').run();
```

There is more to runs, use the `doc` command. For reference, here is the
signature of *sweep*

```matlab
run.sweep(channel, start, end, points, [settle]);
```

where the optional value *settle*, specifies how long to wait after setting
this value (in seconds).

## Plotting measurements

The data files generated by *matlab-qd* are simple ascii files designed to be
easy to load into most software, including gnuplot. That being said,
*matlab-qd* also provides a versatile tool to browse, plot, and load data
outputted by the run classes. Let us fire it up

```matlab
>> brw = qd.gui.FolderBrowser(store.loc);
```

You should be able to find your way around the window that pops up (note, you
can dock the dialog) and plot the IV curves we did earlier. You can plot any
two or three columns in the data file agianst each other. Typically you would
run the *folder browser* in a separate MATLAB instance so that you can view
data as it is being recorded.

The folder browser object (the one we assigned to *brw*) has a few tricks up
its sleave. First of all you can access the currently plotted data through the
*brw.tbl.map* property. This is a *containers.Map* (a standard MATLAB class)
with one entry per column in the data file. The columns are arrays of doubles.

```matlab
>> figure; % Let's do some manual plotting.
>> plot(brw.tbl.map('keithley/v'), brw.tbl.map('keithley/i'));
```

If you name (see below) your channels such that they do not include characters
that are invalid in matlab identifiers (like "/"), then the *tbl* struct gets
the columns as fields allowing you to save some typing. I.e.
`brw.tbl.map('current')` is the same as `brw.tbl.current`.

You can add a column to the currently plotted data using the *inject_column*
method

```matlab
>> voltage = brw.tbl.map('keithley/v');
>> current = brw.tbl.map('keithley/i');
>> brw.inject_column('conductance', current ./ voltage);
```

The computed data is not stored anywhere. Since you might want to compute
some derived column the same way for all data. There is a method to register
a function to be called whenever you plot a data file.

```matlab
>> brw.add_pseudo_column(@(tbl, meta) ...
    brw.tbl.map('keithley/i') ./ brw.tbl.map('keithley/v'), 'conductance');
```

Now all data you plot will get a conductance column. The syntax above is for
lambda functions in MATLAB. Ignore the *meta* parameter for now. You could
also write the above code using a function handle (though only in a file, not
at the prompt). The above code could look like

```matlab
% Put this code in 'load_my_folder_browser.m'

function brw = load_my_folder_browser(device_name)
    brw = qd.gui.FolderBrowser(['D:\Data\Me\' device_name]);
    brw.add_pseudo_column(@conductance);
    % @conductance is a handle to the function below
end

function column = conductance(tbl, meta)
    voltage = tbl.map('keithley/v');
    current = tbl.map('keithley/i');
    column = current ./ voltage;
end
```

Exceptions thrown in a metafunction are turned into warnings, and that column
will be skipped when the data is plotted.

## Advanced topics

### Describing objects (meta information)

Lots of information is available to the computer when a run is started. For
instance, settings of equipment can be queried, temperatures of the cryostat,
etc. and it would be a shame to throw it all out. Therefore *matlab-qd* has an
interface by which instruments and other object can expose a detailed
description of their state. This kind of information is called *meta*
information in *matlab-qd*.

You can see the meta information for an instrument, channel, or setup by using
the *qd.util.describe* function

```matlab
>> qd.util.describe(voltage);
Lots of text ...
```

Notice that the description is broken into two secions. One called *Object*
which contains the description of the *voltage* channel, and one called
*Register* which contains a description of the Keithley. The Keithley is
included because the description of the *voltage* channel refers to it by
name. If the description of the Keithley in turn referred to other objects,
they would also be put in the register, and so forth. 

Here is a simplified version of *qd.util.describe* so you can see what it does

```matlab
function describe(thing)
    register = qd.classes.Register();
    object_description = thing.describe(register);
    register_description = register.describe();
    nicely_print(register_description); % This function doesn't really exist.
    nicely_print(object_description);
end
```

Notice how the *describe* method of *thing* takes the register as an argument,
so that it can add to it.

You may have noticed that each section of the output from *qd.util.describe*
is in [JSON format](http://json.org/). When you execute a run, it does
something similar to *qd.util.describe* and puts the output in a file called
`meta.json` in the data folder. You should look at some of the `meta.json`
files that were generated earlier. Since JSON is a very common and very simple
format, readily available parsers exist for practically every programming
language in existence. This makes it easy to load meta information into
whatever language you use for data processing, MATLAB or otherwise.

### Using channel combinators

Sometimes you want to change the coordinate system you use to set channels.
For instance, you might want to use spherical coordinates for a magnet, or do
a linear transformation on gate channels to eliminate capacitive cross-talk.
For instances such as these, *matlab-qd* has channel combinator, which take
one or more base channels to generate a new set of channels.

TODO

### Writing instrument drivers

TODO

### Subclassing or forgoing the run classes

TODO

### Daemons

TODO