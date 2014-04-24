/*

    File: EAGLView.m
Abstract: This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass. The view content is basically an EAGL surface you render your OpenGL scene into.  Note that setting the view non-opaque will only work if the EAGL surface has an alpha channel.
 Version: 1.21

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Inc. ("Apple") in consideration of your agreement to the following
terms, and your use, installation, modification or redistribution of
this Apple software constitutes acceptance of these terms.  If you do
not agree with these terms, please do not use, install, modify or
redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may
be used to endorse or promote products derived from the Apple Software
without specific prior written permission from Apple.  Except as
expressly stated in this notice, no other rights or licenses, express or
implied, are granted by Apple herein, including but not limited to any
patent rights that may be infringed by your derivative works or by other
works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2010 Apple Inc. All Rights Reserved.


*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "EAGLView.h"

#define USE_DEPTH_BUFFER 1
#define DOCUMENTS_FOLDER [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
#define FILEPATH [DOCUMENTS_FOLDER stringByAppendingPathComponent:[self dateString]]

@interface EAGLView (EAGLViewPrivate)

- (BOOL)createFramebuffer;
- (void)destroyFramebuffer;

@end

@interface EAGLView (EAGLViewSprite)

- (void)setupView;

@end

@implementation EAGLView

@synthesize animationInterval, applicationResignedActive;
@synthesize session;
@synthesize recorder;
@synthesize checkStatus;
@synthesize btnPlay,btnPause,btnRecord;
/*For saving file with name of ddMMYY_hhmmssa.aif*/
- (NSString *) dateString
{
	// return a formatted string for a file name
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	formatter.dateFormat = @"ddMMMYY_hhmmssa";
	return [[formatter stringFromDate:[NSDate date]] stringByAppendingString:@".aif"];
}
/*not used*/
- (NSString *) formatTime: (int) num
{
	// return a formatted ellapsed time string
	int secs = num % 60;
	int min = num / 60;
	if (num < 60) return [NSString stringWithFormat:@"0:%02d", num];
	return	[NSString stringWithFormat:@"%d:%02d", min, secs];
}
/*
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
	// Prepare UI for recording
	{
		// Return to play and record session
		NSError *error;
		if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error])
		{
			NSLog(@"Error: %@", [error localizedDescription]);
			return;
		}
//		self.navigationItem.rightBarButtonItem = BARBUTTON(@"Record", @selector(record));
	}
    
	// Delete the current recording
	[ModalAlert say:@"Deleting recording"];
	//[self.recorder deleteRecording]; <-- too flaky to use
	NSError *error;
	if (![[NSFileManager defaultManager] removeItemAtPath:[self.recorder.url path] error:&error])
		NSLog(@"Error: %@", [error localizedDescription]);
    
	// Release the player
	[player release];
}*/

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
	// Stop monitoring levels, time
	[timer invalidate];
//	self.navigationItem.leftBarButtonItem = nil;
//	self.navigationItem.rightBarButtonItem = nil;
	
	[ModalAlert say:@"File saved to %@", [[self.recorder.url path] lastPathComponent]];
//	self.title = @"Playing back recording...";
	
	// Start playback
	AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:self.recorder.url error:nil];
	player.delegate = self;
	
	// Change audio session for playback
	NSError *error;
	if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error])
	{
		NSLog(@"Error: %@", [error localizedDescription]);
		return;
	}
    
	[player play];
}

- (IBAction) stopRecording
{
	// This causes the didFinishRecording delegate method to fire
	[self.recorder stop];
}

- (IBAction) continueRecording
{
	// resume from a paused recording
	[self.recorder record];
//	self.navigationItem.rightBarButtonItem = BARBUTTON(@"Done", @selector(stopRecording));
//	self.navigationItem.leftBarButtonItem = SYSBARBUTTON(UIBarButtonSystemItemPause, self, @selector(pauseRecording));
}

- (IBAction) pauseRecording
{
	// pause an ongoing recording
	[self.recorder pause];
//	self.navigationItem.leftBarButtonItem = BARBUTTON(@"Continue", @selector(continueRecording));
//	self.navigationItem.rightBarButtonItem = nil;
}

- (BOOL) record
{
	NSError *error;
	
	// Recording settings
	NSMutableDictionary *settings = [NSMutableDictionary dictionary];
	[settings setValue: [NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
	[settings setValue: [NSNumber numberWithFloat:8000.0] forKey:AVSampleRateKey];
	[settings setValue: [NSNumber numberWithInt: 1] forKey:AVNumberOfChannelsKey]; // mono
	[settings setValue: [NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
	[settings setValue: [NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
	[settings setValue: [NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
	
	// File URL
	NSURL *url = [NSURL fileURLWithPath:FILEPATH];
	
	// Create recorder
	self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
	if (!self.recorder)
	{
		NSLog(@"Error: %@", [error localizedDescription]);
		return NO;
	}
	
	// Initialize degate, metering, etc.
	self.recorder.delegate = self;
	self.recorder.meteringEnabled = YES;
	
	
	if (![self.recorder prepareToRecord])
	{
		NSLog(@"Error: Prepare to record failed");
		[ModalAlert say:@"Error while preparing recording"];
		return NO;
	}
	
	if (![self.recorder record])
	{
		NSLog(@"Error: Record failed");
		[ModalAlert say:@"Error while attempting to record audio"];
		return NO;
	}
	
	// Set a timer to monitor levels, current time
	/*timer = [NSTimer scheduledTimerWithTimeInterval:0.1f target:self selector:@selector(updateMeters) userInfo:nil repeats:YES];*/
	
	// Update the navigation bar
//	self.navigationItem.rightBarButtonItem = BARBUTTON(@"Done", @selector(stopRecording));
//	self.navigationItem.leftBarButtonItem = SYSBARBUTTON(UIBarButtonSystemItemPause, self, @selector(pauseRecording));
    
	return YES;
}
- (BOOL) startAudioSession
{
	// Prepare the audio session
	NSError *error;
	self.session = [AVAudioSession sharedInstance];
	
	if (![self.session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error])
	{
		NSLog(@"Error: %@", [error localizedDescription]);
		return NO;
	}
	
	if (![self.session setActive:YES error:&error])
	{
		NSLog(@"Error: %@", [error localizedDescription]);
		return NO;
	}
	
	return self.session.inputIsAvailable;
}



// You must implement this
+ (Class) layerClass
{
	return [CAEAGLLayer class];
}


//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder
{
	if((self = [super initWithCoder:coder])) {
		// Get the layer
		CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
		
		eaglLayer.opaque = YES;
		
		eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
		
		
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
		
		if(!context || ![EAGLContext setCurrentContext:context] || ![self createFramebuffer]) {
			[self release];
			return nil;
		}
		
		animationInterval = 1.0 / 60.0;
		
		[self setupView];
		[self drawView];
	}
	
	return self;
}


- (void)layoutSubviews
{
	[EAGLContext setCurrentContext:context];
	[self destroyFramebuffer];
	[self createFramebuffer];
	[self drawView];
}

/*frame버퍼를 만들어보아요*/
- (BOOL)createFramebuffer
{
    
	glGenFramebuffersOES(1, &viewFramebuffer);
	glGenRenderbuffersOES(1, &viewRenderbuffer);
	
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(id<EAGLDrawable>)self.layer];
	glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
	
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
	if(USE_DEPTH_BUFFER) {
		glGenRenderbuffersOES(1, &depthRenderbuffer);
		glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
		glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
		glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
	}
	
	if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
		NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
		return NO;
	}
	
	return YES;
}


- (void)destroyFramebuffer
{
	glDeleteFramebuffersOES(1, &viewFramebuffer);
	viewFramebuffer = 0;
	glDeleteRenderbuffersOES(1, &viewRenderbuffer);
	viewRenderbuffer = 0;
	
	if(depthRenderbuffer) {
		glDeleteRenderbuffersOES(1, &depthRenderbuffer);
		depthRenderbuffer = 0;
	}
}

- (void)startAnimation
{
	animationTimer = [NSTimer scheduledTimerWithTimeInterval:animationInterval target:self selector:@selector(drawView) userInfo:nil repeats:YES];
	animationStarted = [NSDate timeIntervalSinceReferenceDate];
}

- (void)stopAnimation
{
	[animationTimer invalidate];
	animationTimer = nil;
}

- (void)setAnimationInterval:(NSTimeInterval)interval
{
	animationInterval = interval;
	
	if(animationTimer) {
		[self stopAnimation];
		[self startAnimation];
	}
}


- (void)setupView
{
	
	// Sets up matrices and transforms for OpenGL ES
	glViewport(0, 0, backingWidth, backingHeight);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrthof(0, backingWidth, 0, backingHeight, -1.0f, 1.0f);
	glMatrixMode(GL_MODELVIEW);
	
	// Clears the view with black
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	
	glEnableClientState(GL_VERTEX_ARRAY);
	///glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	
}

// Updates the OpenGL view when the timer fires
- (void)drawView
{
    // the NSTimer seems to fire one final time even though it's been invalidated
    // so just make sure and not draw if we're resigning active
    if (self.applicationResignedActive) return;
    
	// Make sure that you are drawing to the current context
	[EAGLContext setCurrentContext:context];
	
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
	
	[delegate drawView:self forTime:([NSDate timeIntervalSinceReferenceDate] - animationStarted)];
	
	/*
	glRotatef(3.0f, 0.0f, 0.0f, 1.0f);
	
	glClear(GL_COLOR_BUFFER_BIT);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	 */
	
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
	[context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

// Stop animating and release resources when they are no longer needed.
- (void)dealloc
{
	[self stopAnimation];
	
	if([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}
	
	[context release];
	context = nil;
	
	[super dealloc];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([(id)delegate respondsToSelector:@selector(touchesBegan:withEvent:)])
		[delegate touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([(id)delegate respondsToSelector:@selector(touchesMoved:withEvent:)])
		[delegate touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([(id)delegate respondsToSelector:@selector(touchesEnded:withEvent:)])
		[delegate touchesEnded:touches withEvent:event];
}



- (id <EAGLViewDelegate>)delegate { return delegate; }
- (void)setDelegate:(id <EAGLViewDelegate>)v
{
	delegate = v;
}
@end
