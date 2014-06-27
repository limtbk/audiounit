//
//  SelectModeViewController.m
//  MagicRuler
//
//  Created by lim on 6/24/14.
//  Copyright (c) 2014 lim. All rights reserved.
//

#import "SelectModeViewController.h"
#import "AudioPlayController.h"

@interface SelectModeViewController ()

@property (nonatomic, strong) IBOutlet UIButton *startStopButton;

@property (nonatomic, strong) AudioPlayController *playController;

@end

@implementation SelectModeViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)startStopButtonPushed:(id)sender {
    if (!self.startStopButton.selected) {
        self.playController = [AudioPlayController new];
    } else {
        self.playController = nil;
    }
    self.startStopButton.selected = !self.startStopButton.selected;
    NSLog(@"%@", self.playController);
}

@end
