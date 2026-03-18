b = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "amen 1 bar.wav");

//BLOCK 1 SLICES---------------------------------------------------------------

(
//Load buffer and get clip length and server sample rate
~length = b.duration;
~sampleRate = s.sampleRate;

//Declare timing vars. Must be changed manually for a new sample
~bars = 1;
~beats = 4;
~cutsEachBeat = 2; // 1 = quarters, 2 = eighths, 4 = sixteenths

//Calculate sample bpm for use in later calculations
~sampleBpm = (~beats * ~bars * 60) / ~length;

//Calculates slice pointers and adds them to an array
~chopBeat = { |numBars, beatsInBars, cutsPerBeat|
	//Calculate the number of clips there will be
    var numCuts = (numBars * beatsInBars) * cutsPerBeat;
	//Length of each clip in frames
    var clipLength = b.numFrames / numCuts;

	//Fill the array by multiplying the index number (i) by the sample length
	var clips = Array.fill(numCuts, { |i| (i * clipLength).floor}); //[AI]
	//Add one more pointer for the end, so that the last clip can be played by using the last item as its end pointer
	clips = clips.add(b.numFrames);
	//Return clips
    clips;
};

//Call chopBeat to create an array of pointers to the start sample of each clip
~clipPointers = ~chopBeat.(~bars, ~beats, ~cutsEachBeat);
~clipPointers.postln;


//Play a single slice defined by startSampe and endSample
SynthDef(\playClip, {|startSample, endSample, bufnum, durationSeconds, amp|
	//Playhead is a Line that goes between startSample and endSample. Duration derives only from sample length and clip count, so pitch is unaltered
	var playhead = Line.ar(startSample, endSample, durationSeconds);
	//Expects sterio buffer
	var sig = BufRd.ar(2, bufnum, playhead, 0);

	//Free synth once the playhead has reached its end.
    var done = Done.kr(playhead);
	FreeSelf.kr(done);

	Out.ar(0, sig * amp);
}).add; //[AI]

//Function to create \playClip synth (single slice)
~playDrum = {|clipNum, amp|
	//Convert from drum clip numbers (user-readable) to index numbers
	var i = clipNum - 1;
	//Get start and end samples and calculate clip time
	var start = (~clipPointers[i]);
	var end = (~clipPointers[i+1]);
	var clipTime = b.duration / ~clipPointers.size;

	//Debug notes
	("Playing clip number" ++ (i+1)).postln;
	("Start sample:" ++ start).postln;
	("End sample:" ++ end).postln;
	//Create synth
	Synth(\playClip, [\startSample, start, \endSample, end, \bufnum, b.bufnum, \durationSeconds, clipTime, \amp, amp]);
};

//Play drums and bassline defined by arrPointers and bassline
SynthDef(\playRegion, {|bufnum, arrSlices, arrPointers, newBpm, sampleBpm, clipsPerBeat, bassline, amp|
	var i, j, start, end, playhead, triggerRate, trig, durMul, sig, sig2, freq, env;

	//Value to multiply any playback rate arguments like 'rate' in Phasor
    durMul = newBpm / sampleBpm;
	//Setting up a trigger to the bpm
    triggerRate = (newBpm / 60) * clipsPerBeat;
    trig = Impulse.kr(triggerRate);

	//Pulse counter for the trigger determines what part of the drum loop is being played back (index num)
    i = PulseCount.kr(trig) % BufFrames.kr(arrSlices); //[AI]
	Poll.kr(Impulse.kr(triggerRate), i, "Slice: ");
	//Get the value at index position i (drum slice pointer)
    j = Index.kr(arrSlices, i); //[AI]

	//Get start and end samples for the current clip from arrPointers, containing start samples for each clip
    start = Index.kr(arrPointers, j); //[AI]
    end   = Index.kr(arrPointers, j + 1); //[AI]

	//Playhead points at the sample being played back. It phases between start and end sample, which changes with each impulse from trig
    playhead = Phasor.ar(trig, BufRateScale.kr(bufnum) * durMul, start, end, start); //[AI]

	//Frequency of current bass wave selected from bassline array, using the same pulse counter as before
	freq = Index.kr(bassline, i);
	//Env created for bass wave, with trig as the gate
	env = EnvGen.kr(Env.perc(0.01, 1), trig);

	//Drum sig (expects stereo buffer)
    sig = BufRd.ar(2, bufnum, playhead, 0); //[AI]
	//Bass sig
	sig2 = SinOsc.ar(freq, 0, 1, 0) * env;
	//Multiply all outputs by amp to allow volume control
	Out.ar(0, (sig + sig2) * amp);

}).add;

//Function to create \playRegion synth (drum loop and bassline)
~playLoop = { |beatArray, basslineArray, bpm|
var arrPointersBuf, arrSlicesBuf, arrBasslineBuf;

if(beatArray.notEmpty,{
		//Convert each item in beatArray from drum clip numbers (user-readable) to index numbers
		for(0, beatArray.size - 1, { |i|
			beatArray[i] = beatArray[i] - 1;
		});
		//Create buffers out of each array to make them readable on the server
		arrPointersBuf = Buffer.loadCollection(s, ~clipPointers); //[AI]
		arrSlicesBuf = Buffer.loadCollection(s, beatArray); //[AI]
		arrBasslineBuf = Buffer.loadCollection(s, basslineArray); //[AI]

		//Create the synth
		Synth(\playRegion, [
			\bufnum, b.bufnum,
			\arrPointers, arrPointersBuf,
			\arrSlices, arrSlicesBuf,
			\newBpm, bpm, \sampleBpm, ~sampleBpm, \clipsPerBeat, ~cutsEachBeat, \bassline, arrBasslineBuf, \amp, 0.8
		]);
});
};

~makeDrumLoop = { |beatArray, bpm, slicesEachBeat|
	var arrPointersBuf, arrSlicesBuf, arrBasslineBuf, basslineArray;

	basslineArray = [];
	if(beatArray.notEmpty,{
		//Convert each item in beatArray from drum clip numbers (user-readable) to index numbers
		for(0, beatArray.size - 1, { |i|
			beatArray[i] = beatArray[i] - 1;
		});
		//Create buffers out of each array to make them readable on the server
		arrPointersBuf = Buffer.loadCollection(s, ~clipPointers); //[AI]
		arrSlicesBuf = Buffer.loadCollection(s, beatArray); //[AI]
		arrBasslineBuf = Buffer.loadCollection(s, basslineArray); //[AI]

		//Create the synth
		Synth.newPaused(\playRegion, [
			\bufnum, b.bufnum,
			\arrPointers, arrPointersBuf,
			\arrSlices, arrSlicesBuf,
			\newBpm, bpm, \sampleBpm, ~sampleBpm, \clipsPerBeat, slicesEachBeat, \bassline, arrBasslineBuf, \amp, 0.8
		]);
});
};
)

//BLOCK 2 GUI ------------------------------------------------------------------

(
var w, bw, playPause, bpmButt, bpmLabel, barsButt, barsLabel, beatCountButt, beatCountLabel, drumLoop, beatRecording, recording, makePad, makeWhiteKeys, makeBlackKeys, makeBlankKey, makeSkipButton, barsInBeat, beatsInBars, playbackBpm, volSlider, volLabel, vol, basslineRecording, beatProgressLabel, beatProgress, basslineProgressLabel, basslineProgress, recordButt, recordingArray, recordingRow, spbBox, spbLabel, slicesPerBeat;

//Drum pad window always on top, since it contains the record and play/pause button
if(~clipPointers.size > 9 , {
	w = Window("Drum Pad", Rect(200, 400, 330, 260));
},{
	w = Window("Drum Pad", Rect(200, 400, 290, 200));
});

w.alwaysOnTop = true;
bw = Window("Bass Pad", Rect(400, 400, 770, 400));
//Free synths and close all windows on drum pad window close
w.onClose = { drumLoop.free;bw.close;
	recordingArray.do {|item|
		if(item != nil, {
			item.run(false);
		});
	};
};

//Timing vars for new beat
barsInBeat = 1;
beatsInBars = 8;
beatRecording = [1,2,3,4,5,6,7,8];
basslineRecording = [0,0,0,0,0,0,0,0];
recordingArray = Array.newClear(8);
vol = 0.64;

// Play/Pause Button
playPause = Button(w, Rect(30, 30, 110, 30))
.states_([
    ["Play"],
    ["Pause"]
])
.action_({ |but|
    if(but.value == 0, {
		//Stop playback of drum loop
		recordingArray.do {|item|
			if(item != nil, {
				item.run(false);
			});
		};
    }, {

		recordingArray.do {|item|
			if(item != nil, {
				item.run(true);
			});
		};

    });
});

//Recording Button
recordButt = Button(w, Rect( 0,0, 30,30))
.states_([
	["Save"],
	["Stop"]
])
.action_({ |but|
	if(but.value == 0, {
		s.stopRecording;
	}, {
		s.record;
	});
});

// BPM Selector
bpmButt = NumberBox(w, Rect(30, 65, 30, 20))//[AI]
.action_({ |nb|
	//Tie the playbackBpm to bpm selector
    playbackBpm = nb.value;
    ("BPM set to " + playbackBpm).postln;
	//Set drumLoop synth's bpm if playback is live
    if(drumLoop.notNil, {
        drumLoop.set(\newBpm, playbackBpm);
    });
	recordingArray.do {|item|
		if(item != nil, {
			item.set(\newBpm, playbackBpm);
		});
	};
});
//Default value
bpmButt.valueAction = 160;//[AI]
bpmLabel = StaticText(w, Rect(60, 60, 50, 30));
bpmLabel.string = "BPM";



// Bar Count Selector
barsButt = NumberBox(w, Rect(150, 65, 15, 20))//[AI]
.clipLo_(1)
.action_({ |nb|
	//Tie barsInBeat to bars selector
    barsInBeat = nb.value;
    ("Bar count set to " + barsInBeat).postln;
});
//Default value
barsButt.valueAction = 1;//[AI]
barsLabel = StaticText(w, Rect(165, 60, 100, 30));
barsLabel.string = "Bar Count";



//Beat Count Selector
beatCountButt = NumberBox(w, Rect(150, 85, 15, 20))//[AI]
.clipLo_(2)
.action_({ |nb|
	//Tie beatsInBars to beat count selector
	beatsInBars = nb.value;
	("Beat Count per-bar set to " + beatsInBars).postln;
});
//Default time sig 4/4
beatCountButt.valueAction = 4;//[AI]
beatCountLabel = StaticText(w, Rect(165, 80, 100, 30));
beatCountLabel.string = "Beats per-bar";

spbBox = NumberBox(w, Rect(90, 90, 15, 20))
.clipLo_(2)
.action_({|nb|
	slicesPerBeat = nb.value;
});
spbBox.valueAction = 2;
spbLabel = StaticText(w, Rect(105, 75, 50, 50));
spbLabel.string = "Slices per-beat";

// Recording Button
recording = Button(w, Rect(150, 30, 110, 30))
.states_([
	//Turn red when recording
    ["Record", Color.black, Color.white],
    ["Stop", Color.white, Color.red]
])
.action_({ |b|
	//If recording started, make empty arrays for beat and bassline recording
    if(b.value == 1, {
		/*playPause.valueAction = 0;*/
		beatProgress = 0;
		basslineProgress = 0;
        beatRecording = Array.new((barsInBeat * beatsInBars) * slicesPerBeat);
		beatProgressLabel.string = beatProgress + "/" + ((barsInBeat * beatsInBars) * slicesPerBeat);
		basslineRecording = Array.new((barsInBeat * beatsInBars) * slicesPerBeat);
		basslineProgressLabel.string = basslineProgress + "/" + ((barsInBeat * beatsInBars) * slicesPerBeat);
    });
});

//Recording progress labels
beatProgress = 0;
basslineProgress = 0;
beatProgressLabel = StaticText(w, Rect(150, 20, 110, 10));
basslineProgressLabel = StaticText(bw, Rect(150, 20, 40, 10));


//Function to create a drum pad button
makePad = { |label, num, x, y, height = 30|
	var synth;
    Button(w, Rect(x, y, 50, height)) //[AI]
    .states_([[label]]) //[AI]
    .action_({
		//Play the drum allocated to this button
        ~playDrum.(num, vol * 1.5);

		//If recording is active, add the drum clip number to beat recording array
        if(recording.value == 1) {
            beatRecording.add(num);
			//Update progress label
			beatProgress = beatProgress+ 1;
			beatProgressLabel.string = beatProgress + "/" + ((barsInBeat * beatsInBars) * slicesPerBeat);
            beatRecording.postln;
			//Stop recording once the beat has reached the correct size
			if(beatRecording.size == ((barsInBeat * beatsInBars) * slicesPerBeat)) {
                recording.value = 0;
				//add a synth to array
				synth = ~makeDrumLoop.(beatRecording,playbackBpm, slicesPerBeat);
				// recordingArray = recordingArray.add(synth);
				"Added:".postln;
				recordingArray.postln;
				recordingRow.(synth, beatRecording,slicesPerBeat);
			};
		};
    });
};



//Function to craete a white bass key button
makeWhiteKeys = { |label, num, x, y|
    Button(bw, Rect(x, y, 50, 350)) //[AI]
    .states_([[label, Color.black, Color.white]])
    .action_({
		//Play the frequency allocated to this button
		{
			var env = EnvGen.kr(Env.perc(0.01, 1, curve: -4) ,doneAction: 2);
			var sig = SinOsc.ar(num, 0, 1, 0) * env;
			Out.ar(0, sig * (vol * 1.25) !2);
		}.play; //[AI]

		//If recording is active, add the frequency number to beat recording array
        if(recording.value == 1) {
            basslineRecording.add(num);
            basslineRecording.postln;

			//Update progress label
			basslineProgress = basslineProgress+ 1;
			basslineProgressLabel.string = basslineProgress + "/" + ((barsInBeat * beatsInBars) * ~cutsEachBeat);

			//Stop recording once the beat has reached the correct size
			if(basslineRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat)) && beatRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat))) {
                recording.value = 0;
            };
		};
    });
};
//Function to craete a black bass key button
makeBlackKeys = { |label, num, x, y|
    Button(bw, Rect(x, y, 25, 150)) //[AI]
    .states_([[label, Color.white, Color.black]])
    .action_({
		//Play the frequency allocated to this button
		{
			var env = EnvGen.kr(Env.perc(0.01, 1, curve: -4) ,doneAction: 2);
			var sig = SinOsc.ar(num, 0, 1, 0) * env;
			Out.ar(0, sig * (vol * 1.25) !2);
		}.play; //[AI]

		//If recording is active, add the frequency number to beat recording array
        if(recording.value == 1) {
            basslineRecording.add(num);
            basslineRecording.postln;

			//Update progress label
			basslineProgress = basslineProgress+ 1;
			basslineProgressLabel.string = basslineProgress + "/" + ((barsInBeat * beatsInBars) * ~cutsEachBeat);
			//Stop recording once the beat has reached the correct size
			if(basslineRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat)) && beatRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat))) {
                recording.value = 0;
            };
		};
    });
};


//Function to craete a style-less bass pad button
makeBlankKey = { |label, num, x, y|
    Button(bw, Rect(x, y, 50, 25)) //[AI]
    .states_([[label, Color.black, Color.white]])
    .action_({

		//If recording is active, add the frequency number to beat recording array
        if(recording.value == 1) {
            basslineRecording.add(num);
            basslineRecording.postln;

			//Update progress label
			basslineProgress = basslineProgress+ 1;
			basslineProgressLabel.string = basslineProgress + "/" + ((barsInBeat * beatsInBars) * ~cutsEachBeat);

			//Stop recording once the beat has reached the correct size
			if(basslineRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat)) && beatRecording.size == ((barsInBeat * beatsInBars) * (~cutsEachBeat))) {
                recording.value = 0;
            };
		};
    });
};

recordingRow = {|synth, recording, spb|
	var onBut, resetBut, top, synthPos, vol;
	top = w.bounds.height;
	synthPos = recordingArray.indexOf(nil);
		recording.postln;
	w.bounds = Rect(w.bounds.left, w.bounds.top, w.bounds.width, w.bounds.height + 30);
	onBut = Button(w, Rect(30, top, 30, 20))
	.states_([["Off"], ["On"]])
	.action_({|butt|
		var syn, index;
		index = synthPos;
		syn = synth;
		index.postln;
		if(butt.value == 0, {

			recordingArray[index].run(false);
			recordingArray[index] = nil;
		},{
			recordingArray[index] = syn;

			if(playPause.value == 1, {
				recordingArray[index].run(true);
			});
		});
		recordingArray.postln;
	});
	onBut.valueAction = 1;

	vol = Slider(w, Rect(65, top, 160, 20))
	.action_({|sl|
		var index = synthPos;
		recordingArray[index].set(\amp, sl.value * 1.25);
	});
	vol.valueAction = 0.64;

	resetBut = Button(w, Rect(230, top, 30, 20))
		.states_([["Cue"]])
		.action_({
			var index = synthPos;
			playPause.valueAction = 0;
			recordingArray[index].free;
			recordingArray[index] = ~makeDrumLoop.(recording, playbackBpm, spb);
			"Reset".postln;
		});
};

//Create drum pads
makePad.("Skip Beat", 0, 30, 90, 20);
makePad.("Clip 1", 1,  30, 120);
makePad.("Clip 2", 2,  90, 120);
makePad.("Clip 3", 3, 150, 120);
makePad.("Clip 4", 4, 210, 120);
makePad.("Clip 5", 5,  30, 160);
makePad.("Clip 6", 6,  90, 160);
makePad.("Clip 7", 7, 150, 160);
makePad.("Clip 8", 8, 210, 160);
if(~clipPointers.size > 9){
	makePad.("Clip 9", 9,  30, 200);
	makePad.("Clip 10", 10,  90, 200);
	makePad.("Clip 11", 11, 150, 200);
	makePad.("Clip 12", 12, 210, 200);
	makePad.("Clip 13", 13,  30, 240);
	makePad.("Clip 14", 14,  90, 240);
	makePad.("Clip 15", 15, 150, 240);
	makePad.("Clip 16", 16, 210, 240);
};

//Create bass keys
//White keys
makeWhiteKeys.("C1", 32.7, 10, 30);
makeWhiteKeys.("D1", 36.71, 60, 30);
makeWhiteKeys.("E1", 41.2, 110, 30);
makeWhiteKeys.("F1", 43.65, 160, 30);
makeWhiteKeys.("G1", 49, 210, 30);
makeWhiteKeys.("A1", 55, 260, 30);
makeWhiteKeys.("B1", 61.74, 310, 30);
makeWhiteKeys.("C2", 65.41, 360, 30);
makeWhiteKeys.("D2", 73.42, 410, 30);
makeWhiteKeys.("E2", 82.4, 460, 30);
makeWhiteKeys.("F2", 87.3, 510, 30);
makeWhiteKeys.("G2", 98, 560, 30);
makeWhiteKeys.("A2", 110, 610, 30);
makeWhiteKeys.("B2", 123.48, 660, 30);
makeWhiteKeys.("C3", 130.82, 710, 30);
//Black keys
makeBlackKeys.("D♭1", 34.65, 47.5, 30);
makeBlackKeys.("E♭1", 38.89, 95.5, 30);
makeBlackKeys.("G♭1", 46.25, 197.5, 30);
makeBlackKeys.("A♭1", 51.91, 250.5, 30);
makeBlackKeys.("B♭1", 58.27, 297.5, 30);
makeBlackKeys.("D♭2", 69.3, 397.5, 30);
makeBlackKeys.("E♭2", 77.78, 447.5, 30);
makeBlackKeys.("G♭2", 92.5, 547.5, 30);
makeBlackKeys.("A♭2", 103.82, 597.5, 30);
makeBlackKeys.("B♭2", 116.54, 647.5, 30);
//Blank key
makeBlankKey.("Skip", 0, 10, 5);

bw.front;
w.front;
)