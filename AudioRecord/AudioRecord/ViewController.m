//
//  ViewController.m
//  AudioRecord
//
//  Created by lim on 6/28/14.
//  Copyright (c) 2014 lim. All rights reserved.
//

#import "ViewController.h"
#import "AudioController.h"
#import <Foundation/Foundation.h>

@interface ViewController ()

@property (nonatomic, strong) AudioController *audioController;

@end

@implementation ViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.audioController = [AudioController new];
    [self.audioController startAudio];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
