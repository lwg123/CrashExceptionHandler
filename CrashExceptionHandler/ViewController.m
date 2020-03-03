//
//  ViewController.m
//  CrashExceptionHandler
//
//  Created by weiguang on 2020/2/27.
//  Copyright © 2020 weiguang. All rights reserved.
//

#import "ViewController.h"

typedef struct Test
{
    int a;
    int b;
}Test;
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}
- (IBAction)SignalHandler {
    
    //1.信号量
    Test *pTest = {1,2};
    free(pTest);
    pTest->a = 5;
}

- (IBAction)ExceptionHandler {
    
    //2.ios崩溃
    NSArray *array= @[@"tom",@"xxx",@"ooo"];
    [array objectAtIndex:5];
}

@end
